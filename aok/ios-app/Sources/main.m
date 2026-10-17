// AOK QEMU Bench -- the race of aok, on a device.
//
// Boots the same RISC-V guest (kernel, initramfs and OpenSBI in the bundle) on the QEMU in
// Frameworks/qemu-riscv64-softmmu.framework -- or, for a label that begins "aarch64", the arm64 guest on
// qemu-aarch64-softmmu.framework; for "x86_64" and "i386", the 64-bit and the 32-bit PC guest, both on
// qemu-x86_64-softmmu.framework -- which is the tctiSH fork built with --enable-aok-gadgets, and
// measures each workload the way cycwrap.c does on a Mac: this process's cycle and instruction counters
// read at the guest's WL-START and RESULT lines. Results are appended to Documents/results.txt, one WL line
// per workload in cycwrap's format, then "DONE label".
//
// The run is configured by the environment the app is launched with (devicectl ... process launch
// --environment-variables):
//   QEMU_AOK        "0" leaves every block to QEMU's own engine; anything else, AOK's gadgets (read by QEMU)
//   AOKQ_LABEL      the WL lines' label, e.g. riscv64-aokq-1 (arch-engine-round, as summarize.py wants)
//   AOKQ_WORKLOADS  comma separated, as bench/run1.sh names them; default the six of the race
//   AOKQ_SMP        guest CPUs, default 1
//   AOKQ_ACCEL      QEMU's -accel, default tcg,tb-size=256 (tcg,tb-size=256,thread=multi: the CPUs in parallel)
//   AOKQ_CPU        QEMU's -cpu, default the guest's (qemu64,+rdrand for x86_64)
//   AOKQ_EXIT       exit when the guest has shut down, so that QEMU_AOK_STATS (printed at exit) is written
//   AOKQ_HOLD       keep the screen on this many seconds after the run (then exit, with AOKQ_EXIT), so a
//                   device with a short Auto-Lock does not lock between one run and the next
//   AOKQ_HOLD_ONLY  run nothing: keep the screen on for AOKQ_HOLD seconds (default an hour), then let go
// QEMU's own messages go to Documents/qemu.log, the guest's console to Documents/serial.log.
// QEMU can be started once per process, so one launch is one run.

#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/resource.h>
#include <sys/sysctl.h>

int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer);

static UITextView *text_view;       // nil until the scene connects; the transcript is kept for it
static NSMutableString *transcript;
static NSString *documents;
static double tick_ns;

static void say(NSString *line) {
    NSString *path = [documents stringByAppendingPathComponent:@"results.txt"];
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        fprintf(f, "%s\n", line.UTF8String);
        fclose(f);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [transcript appendFormat:@"%@\n", line];
        text_view.text = transcript;
        [text_view scrollRangeToVisible:NSMakeRange(transcript.length, 0)];
    });
}

static const char *env_or(const char *name, const char *fallback) {
    const char *v = getenv(name);
    return v && *v ? v : fallback;
}

struct snap { uint64_t cycles, insns, pinsns, cpu, wall; int has_p; };
static struct snap take(void) {
    struct snap s = {0};
    struct rusage_info_v6 v6;
    struct rusage_info_v4 v4;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *) &v6) == 0) {
        s.cycles = v6.ri_cycles; s.insns = v6.ri_instructions; s.pinsns = v6.ri_pinstructions;
        s.cpu = v6.ri_user_time + v6.ri_system_time; s.has_p = 1;
    } else if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *) &v4) == 0) {
        s.cycles = v4.ri_cycles; s.insns = v4.ri_instructions;
        s.cpu = v4.ri_user_time + v4.ri_system_time;
    }
    s.wall = mach_absolute_time();
    return s;
}

// Follows the guest's serial console, which QEMU writes to a file, and brackets each workload.
static void *reader(void *arg) {
    const char *path = arg;
    const char *label = env_or("AOKQ_LABEL", "riscv64-aokq-1");
    FILE *f = NULL;
    char line[4096], name[64] = "";
    size_t len = 0;
    struct snap a = {0};
    for (;;) {
        if (!f && !(f = fopen(path, "r"))) { usleep(2000); continue; }
        int c = fgetc(f);
        if (c == EOF) { clearerr(f); usleep(1000); continue; }
        if (c != '\n') { if (c != '\r' && len < sizeof line - 1) line[len++] = (char) c; continue; }
        line[len] = 0; len = 0;
        char n[64]; long guest_ms;
        if (sscanf(line, "WL-START %63s", n) == 1) {
            strcpy(name, n);
            a = take();
        } else if (sscanf(line, "RESULT %63s %ld", n, &guest_ms) == 2 && !strcmp(n, name)) {
            struct snap b = take();
            uint64_t insns = b.insns - a.insns;
            say([NSString stringWithFormat:@"WL %s %s %.0f %.0f %llu %llu %ld %.0f", label, name,
                 (b.wall - a.wall) * tick_ns / 1e6, (b.cpu - a.cpu) * tick_ns / 1e6,
                 (unsigned long long) (b.cycles - a.cycles), (unsigned long long) insns, guest_ms,
                 b.has_p && insns ? 100.0 * (b.pinsns - a.pinsns) / insns : -1.0]);
            name[0] = 0;
        } else if (!strncmp(line, "BENCH-", 6) || !strncmp(line, "CHECK", 5) || !strncmp(line, "FP ", 3) ||
                   !strncmp(line, "STRESS", 6) || strstr(line, "panic") || strstr(line, "aok:")) {
            say([NSString stringWithUTF8String:line]);
        }
    }
    return NULL;
}

// The screen stays on for @secs more seconds, and is then the device's again: an app left in front with the
// idle timer off held an M4 iPad's screen on all night, and the iPad was found half-responsive in the morning
// (2026-10-14). So a hold always ends.
static void hold_then_let_go(long secs) {
    if (secs > 0) {
        say([NSString stringWithFormat:@"HOLD %ld s", secs]);
        sleep((unsigned) secs);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ UIApplication.sharedApplication.idleTimerDisabled = NO; });
    if (getenv("AOKQ_EXIT")) {
        usleep(200000);
        exit(0);
    }
}

static void *run_qemu(void *arg) {
    if (getenv("AOKQ_HOLD_ONLY")) {
        hold_then_let_go(atol(env_or("AOKQ_HOLD", "3600")));
        return NULL;
    }
    NSString *bundle = NSBundle.mainBundle.resourcePath;
    // The label's first part is the guest, one of the Mac race's four. The 32-bit PC guest runs on the
    // x86-64 QEMU, as it does in the VM app. An x86 guest gets rdrand and a kernel told to trust it: with
    // no source of entropy it waits a quarter of a minute for some, whichever engine runs it.
    static const struct { const char *label, *qemu, *machine, *cpu, *console, *kernel, *initrd, *extra; } guests[] = {
        { "riscv64", "riscv64", "virt", "rv64", "ttyS0", "Image-lts-riscv64", "initramfs-riscv64.cpio", "" },
        { "aarch64", "aarch64", "virt", "cortex-a72", "ttyAMA0", "vmlinuz-virt-aarch64", "initramfs-aarch64.cpio", "" },
        { "x86_64", "x86_64", "q35", "qemu64,+rdrand", "ttyS0", "vmlinuz-virt-x86_64", "initramfs-x86_64.cpio",
          "random.trust_cpu=on " },
        { "i386", "x86_64", "q35", "qemu32,+rdrand", "ttyS0", "vmlinuz-virt-x86", "initramfs-x86.cpio",
          "random.trust_cpu=on " },
    };
    const char *label = env_or("AOKQ_LABEL", "riscv64-aokq-1");
    int g = 0;
    for (int i = 0; i < 4; i++) {
        if (strncmp(label, guests[i].label, strlen(guests[i].label)) == 0) g = i;
    }
    NSString *name = [NSString stringWithFormat:@"qemu-%s-softmmu", guests[g].qemu];
    NSString *framework = [NSBundle.mainBundle.privateFrameworksPath
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", name, name]];
    NSString *serial = [documents stringByAppendingPathComponent:@"serial.log"];
    NSString *append = [NSString stringWithFormat:@"console=%s rdinit=/init quiet %sbench=%s",
                        guests[g].console, guests[g].extra,
                        env_or("AOKQ_WORKLOADS", "coremark,nbody,python,xz,sha256,awk")];
    NSArray<NSString *> *args = @[
        [NSString stringWithFormat:@"qemu-system-%s", guests[g].qemu], @"-M", @(guests[g].machine),
        @"-cpu", @(env_or("AOKQ_CPU", guests[g].cpu)), @"-smp", @(env_or("AOKQ_SMP", "1")),
        @"-m", @"1024", @"-accel", @(env_or("AOKQ_ACCEL", "tcg,tb-size=256")), @"-display", @"none", @"-monitor", @"none",
        @"-serial", [@"file:" stringByAppendingString:serial], @"-no-reboot", @"-L", bundle,
        @"-kernel", [bundle stringByAppendingPathComponent:@(guests[g].kernel)],
        @"-initrd", [bundle stringByAppendingPathComponent:@(guests[g].initrd)],
        @"-append", append,
        // (a machine's default network card wants an option ROM the bundle does not carry)
        @"-nic", @"none",
    ];
    int argc = (int) args.count;
    char **argv = calloc(argc + 1, sizeof *argv);
    for (int i = 0; i < argc; i++) argv[i] = strdup(args[i].UTF8String);

    truncate(serial.fileSystemRepresentation, 0);
    NSString *log = [documents stringByAppendingPathComponent:@"qemu.log"];
    fprintf(stderr, "aokq: QEMU's messages go to %s\n", log.UTF8String);
    freopen(log.fileSystemRepresentation, "w", stderr);
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_t t;
    pthread_create(&t, NULL, reader, strdup(serial.fileSystemRepresentation));

    void *dll = dlopen(framework.fileSystemRepresentation, RTLD_NOW);
    if (!dll) { say([NSString stringWithFormat:@"ERROR dlopen: %s", dlerror()]); return NULL; }
    void (*qemu_init)(int, char **) = dlsym(dll, "qemu_init");
    int (*qemu_main_loop)(void) = dlsym(dll, "qemu_main_loop");
    void (*qemu_cleanup)(int) = dlsym(dll, "qemu_cleanup");
    if (!qemu_init || !qemu_main_loop || !qemu_cleanup) { say(@"ERROR QEMU's entry points are missing"); return NULL; }
    say([NSString stringWithFormat:@"START %s QEMU_AOK=%s smp=%s accel=%s cpu=%s thermal=%ld",
         env_or("AOKQ_LABEL", "riscv64-aokq-1"), env_or("QEMU_AOK", "1"), env_or("AOKQ_SMP", "1"),
         env_or("AOKQ_ACCEL", "tcg,tb-size=256"), env_or("AOKQ_CPU", "default"),
         (long) NSProcessInfo.processInfo.thermalState]);
    qemu_init(argc, argv);
    int status = qemu_main_loop();
    usleep(300000);     // let the reader drain the console
    say([NSString stringWithFormat:@"DONE %s status=%d thermal=%ld", env_or("AOKQ_LABEL", "riscv64-aokq-1"), status,
         (long) NSProcessInfo.processInfo.thermalState]);
    qemu_cleanup(status);
    // The screen was kept on for the run, and for AOKQ_HOLD seconds after it if asked (hold_then_let_go).
    hold_then_let_go(atol(env_or("AOKQ_HOLD", "0")));
    return NULL;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    tick_ns = (double) tb.numer / tb.denom;
    documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:NULL];
    transcript = [NSMutableString new];
    app.idleTimerDisabled = YES;

    char machine[64] = "?";
    size_t size = sizeof machine;
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    say([NSString stringWithFormat:@"DEVICE %s iOS %@ cores %lu", machine, UIDevice.currentDevice.systemVersion,
         (unsigned long) NSProcessInfo.processInfo.activeProcessorCount]);

    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_create(&t, &attr, run_qemu, NULL);
    return YES;
}
@end

// The window. A scene, because UIKit no longer launches an app built with a current SDK without one.
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *) scene];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    text_view = [[UITextView alloc] initWithFrame:vc.view.bounds];
    text_view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text_view.editable = NO;
    text_view.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    text_view.text = transcript;
    [vc.view addSubview:text_view];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
}
@end

int main(int argc, char *argv[]) {
    fprintf(stderr, "aokq: started\n");
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
