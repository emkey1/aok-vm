// cycwrap [-q] LABEL CMD [ARGS...] -- run CMD and read its output. For every workload the guest brackets with
// a "WL-START name" line and a "RESULT name ..." line, print what the whole host process spent in between:
//   WL label name wall_ms cpu_ms cycles instructions guest_wall_ms pcore_percent
// Cycles and instructions come from proc_pid_rusage, so a QEMU guest's boot is not in the figure and nothing
// has to be subtracted. They do not move with the machine's clock speed. Cycles do move with the core class,
// so pcore_percent says how much of the work ran on the fastest class ("Super" on an M5 Max), and -q starts
// CMD at user-interactive QoS, which is what keeps it there.
#include <libproc.h>
#include <mach/mach_time.h>
#include <spawn.h>
#include <pthread/spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/qos.h>
#include <sys/wait.h>

extern char **environ;
static double tick_ns;
struct snap { uint64_t cycles, insns, pinsns, cpu, wall; };
static struct snap take(pid_t pid) {
    struct rusage_info_v6 ri;
    struct snap s = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *) &ri) == 0) {
        s.cycles = ri.ri_cycles; s.insns = ri.ri_instructions; s.pinsns = ri.ri_pinstructions;
        s.cpu = ri.ri_user_time + ri.ri_system_time;
    }
    s.wall = mach_absolute_time();
    return s;
}
int main(int argc, char **argv) {
    int qos = 0;
    if (argc > 1 && !strcmp(argv[1], "-q")) { qos = 1; argv++; argc--; }
    if (argc < 3) return 2;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb); tick_ns = (double) tb.numer / tb.denom;
    int p[2]; if (pipe(p)) return 1;
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_adddup2(&fa, p[1], 2);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    posix_spawn_file_actions_addclose(&fa, p[1]);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", 0, 0);
    posix_spawnattr_t at; posix_spawnattr_init(&at);
    if (qos) posix_spawnattr_set_qos_class_np(&at, QOS_CLASS_USER_INTERACTIVE);
    pid_t pid;
    if (posix_spawnp(&pid, argv[2], &fa, &at, argv + 2, environ)) { perror("spawn"); return 1; }
    close(p[1]);
    FILE *in = fdopen(p[0], "r");
    char line[4096], name[64] = ""; struct snap a = {0};
    while (fgets(line, sizeof line, in)) {
        char n[64]; long gw;
        if (sscanf(line, "WL-START %63s", n) == 1) { strcpy(name, n); a = take(pid); }
        else if (sscanf(line, "RESULT %63s %ld", n, &gw) == 2 && !strcmp(n, name)) {
            struct snap b = take(pid);
            uint64_t ins = b.insns - a.insns;
            printf("WL %s %s %.0f %.0f %llu %llu %ld %.0f\n", argv[1], name, (b.wall - a.wall) * tick_ns / 1e6,
                   (b.cpu - a.cpu) * tick_ns / 1e6, (unsigned long long) (b.cycles - a.cycles),
                   (unsigned long long) ins, gw, ins ? 100.0 * (b.pinsns - a.pinsns) / ins : 0.0);
            fflush(stdout); name[0] = 0;
        }
    }
    int st; waitpid(pid, &st, 0);
    return 0;
}
