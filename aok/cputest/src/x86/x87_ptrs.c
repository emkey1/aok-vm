// x87_ptrs.c -- what the x87 keeps of its last instruction, against what real
// hardware (an AMD Ryzen, camd, -m32 and 64-bit) keeps:
//
//  * Every instruction but the control ones leaves its address (FIP), cs
//    (FCS) and opcode (FOP: the ModRM byte after the first byte's low three
//    bits). FNOP, FINCSTP, FDECSTP, FFREE(P) and the undocumented aliases
//    count; FNINIT, FLDCW, FNSTCW, FNSTSW, FNCLEX, FWAIT, FENI, FDISI and
//    FSETPM do not. FNINIT and XRSTOR's initial x87 state zero them all.
//  * A memory form also leaves its operand's offset (FDP: not fs's or gs's
//    base, and 32 bits in 32-bit code) and the selector of the segment it
//    used (FDS): a prefix's in 32-bit code (64-bit code ignores es, cs, ss
//    and ds), else ss's for a base of esp/rsp or ebp/rbp (not r12, r13),
//    else ds's.
//  * FXSAVE and XSAVE store FOP, FIP and FDP only while an exception is
//    pending, zeros otherwise: FIP | FCS << 32 and FDP | FDS << 32, or with
//    REX.W all 64 bits. FXRSTOR loads them whatever the status word says;
//    its REX.W form takes 48 bits, sign-extended, and leaves no selectors.
//  * The #MF a pending exception raises at the next waiting instruction
//    shows the instruction that raised it, in the SIGFPE handler's saved
//    state (a Windows exception handler reads it there). A 64-bit kernel
//    gives a 32-bit program's frame its own cs there, and no opcode.
#define _GNU_SOURCE
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>

static unsigned long checks, bad;
static void check(const char *what, uint64_t got, uint64_t want) {
    checks++;
    if (got != want && bad++ < 60)
        printf("FAIL %s: %#llx, want %#llx\n", what, (unsigned long long) got, (unsigned long long) want);
}

static uint8_t b[2048] __attribute__((aligned(64)));
static float one = 1.0f, fzero = 0.0f, fa[2] = {0.0f, 1.0f};
extern char x87_ptrs_mf[];      // the insn whose exception the #MF is
static short two = 2;
static uint16_t cs, ds, ss, es, fs, gs;
static uint64_t rd64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static uint32_t rd32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t rd16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }

// FNSTENV's 32-bit image: FIP, FCS, FOP, FDP, FDS. Then FLDCW, to undo the
// masking FNSTENV does.
static struct { uint32_t fip, fdp; uint16_t fcs, fop, fds; } e;
static void env(void) {
    memset(b, 0xaa, 32);
    __asm__ volatile("fnstenv %0\n fldcw %0" : "+m"(*(uint8_t (*)[28]) b));
    e.fip = rd32(b + 12);
    e.fcs = rd16(b + 16);
    e.fop = rd16(b + 18) & 0x7ff;
    e.fdp = rd32(b + 20);
    e.fds = rd16(b + 24);
}
static void last(const char *what, unsigned long ip, unsigned op) {
    char w[96];
    env();
    snprintf(w, sizeof w, "%s: fip", what); check(w, e.fip, (uint32_t) ip);
    snprintf(w, sizeof w, "%s: fcs", what); check(w, e.fcs, cs);
    snprintf(w, sizeof w, "%s: fop", what); check(w, e.fop, op);
}
static void data(const char *what, unsigned long ip, unsigned op, unsigned long dp, uint16_t sel) {
    char w[96];
    last(what, ip, op);
    snprintf(w, sizeof w, "%s: fdp", what); check(w, e.fdp, (uint32_t) dp);
    snprintf(w, sizeof w, "%s: fds", what); check(w, e.fds, sel);
}

#ifdef __x86_64__
#define HERE "lea 1f(%%rip), %0\n"
#define AX "(%%rax)"
#define W64 1
#else
#define HERE "call 2f\n2: pop %0\n add $(1f-2b), %0\n"
#define AX "(%%eax)"
#define W64 0
#endif
// insn at label 1, its address in ip
#define AT(insn, ...) __asm__ volatile(HERE "1: " insn : "=&r"(ip) : __VA_ARGS__)
#define AT0(insn) __asm__ volatile(HERE "1: " insn : "=&r"(ip))

static sigjmp_buf jb;
static volatile uint64_t s_ip, s_dp, s_op, s_cs;
static volatile int sig;
static void on_fpe(int s, siginfo_t *si, void *uc_) {
    ucontext_t *uc = uc_;
    (void) si;
    sig = s;
#ifdef __x86_64__
    s_ip = uc->uc_mcontext.fpregs->rip;
    s_dp = uc->uc_mcontext.fpregs->rdp;
    s_op = uc->uc_mcontext.fpregs->fop;
#else
    s_ip = uc->uc_mcontext.fpregs->ipoff;
    s_dp = uc->uc_mcontext.fpregs->dataoff;
    s_cs = uc->uc_mcontext.fpregs->cssel;
#endif
    siglongjmp(jb, 1);
}

int main(void) {
    unsigned long ip, ip2;
    __asm__("mov %%cs, %0\n mov %%ds, %1\n mov %%ss, %2\n mov %%es, %3\n mov %%fs, %4\n mov %%gs, %5"
            : "=r"(cs), "=r"(ds), "=r"(ss), "=r"(es), "=r"(fs), "=r"(gs));

    // FNINIT: all zero
    __asm__ volatile("fld1\n fninit");
    env();
    check("fninit fip", e.fip, 0); check("fninit fcs", e.fcs, 0); check("fninit fop", e.fop, 0);
    check("fninit fdp", e.fdp, 0); check("fninit fds", e.fds, 0);

    // Memory forms, each of a kind of gadget
    __asm__ volatile("fninit");
    AT("flds " AX, "a"(&one));                    data("flds m32", ip, 0x100, (unsigned long) &one, ds);
    AT("fiadds " AX, "a"(&two));                  data("fiadds m16", ip, 0x600, (unsigned long) &two, ds);
    AT("fmuls 4" AX, "a"(&fa[0]));                data("fmuls 4(r)", ip, 0x048, (unsigned long) &fa[1], ds);
    AT("fsts " AX, "a"(&b[1024]) : "memory");     data("fsts m32", ip, 0x110, (unsigned long) &b[1024], ds);
    AT("fstpt " AX, "a"(&b[1024]) : "memory");    data("fstpt m80", ip, 0x338, (unsigned long) &b[1024], ds);
    AT("fldt " AX, "a"(&b[1024]));                data("fldt m80", ip, 0x328, (unsigned long) &b[1024], ds);
    AT("fistps " AX, "a"(&b[1040]) : "memory");   data("fistps m16", ip, 0x718, (unsigned long) &b[1040], ds);
    AT("fildll " AX, "a"(&b[1040]));              data("fildll m64", ip, 0x728, (unsigned long) &b[1040], ds);
    AT("fbstp " AX, "a"(&b[1056]) : "memory");    data("fbstp m80", ip, 0x730, (unsigned long) &b[1056], ds);
    AT("fbld " AX, "a"(&b[1056]));                data("fbld m80", ip, 0x720, (unsigned long) &b[1056], ds);
    AT("fcomps " AX, "a"(&one));                  data("fcomps m32", ip, 0x018, (unsigned long) &one, ds);
    __asm__ volatile("fninit");
#ifdef __x86_64__
    AT0("flds one(%%rip)");                       data("flds rip-relative", ip, 0x105, (unsigned long) &one, ds);
    __asm__ volatile("mov %1, %%r12\n" HERE "1: flds (%%r12)" : "=&r"(ip) : "r"(&one) : "r12");
    data("flds (r12): ds", ip, 0x104, (unsigned long) &one, ds);
    __asm__ volatile("mov %1, %%r13\n" HERE "1: flds 0(%%r13)" : "=&r"(ip) : "r"(&one) : "r13");
    data("flds 0(r13): ds", ip, 0x145, (unsigned long) &one, ds);
    AT("flds %%ss:(%%rax)", "a"(&one));           data("flds ss:(rax): ds", ip, 0x100, (unsigned long) &one, ds);
    AT("flds %%cs:(%%rax)", "a"(&one));           data("flds cs:(rax): ds", ip, 0x100, (unsigned long) &one, ds);
    __asm__ volatile("sub $128, %%rsp\n push %1\n" HERE "1: flds (%%rsp)\n add $136, %%rsp"
                     : "=&r"(ip) : "r"(0x3f800000UL) : "memory");
    env(); check("flds (rsp): fds", e.fds, ss); check("flds (rsp): fip", e.fip, (uint32_t) ip);
    __asm__ volatile("xchg %%rbp, %%rax\n" HERE "1: flds 0(%%rbp)\n xchg %%rbp, %%rax"
                     : "=&r"(ip) : "a"(&one) : "memory");
    data("flds 0(rbp): ss", ip, 0x145, (unsigned long) &one, ss);
    // fs: the offset, not the address; and a negative one, all 64 bits of it
    AT0("flds %%fs:0");                           data("flds fs:0", ip, 0x104, 0, fs);
    AT0("flds %%fs:-4");                          data("flds fs:-4", ip, 0x104, 0xfffffffc, fs);
#else
    AT0("flds %%gs:0");                           data("flds gs:0", ip, 0x105, 0, gs);
    AT0("flds %%gs:-4");                          data("flds gs:-4: wraps", ip, 0x105, 0xfffffffc, gs);
    AT("flds %%ss:(%%eax)", "a"(&one));           data("flds ss:(eax)", ip, 0x100, (unsigned long) &one, ss);
    AT("flds %%es:(%%eax)", "a"(&one));           data("flds es:(eax)", ip, 0x100, (unsigned long) &one, es);
    AT("flds %%cs:(%%eax)", "a"(&one));           data("flds cs:(eax)", ip, 0x100, (unsigned long) &one, cs);
    // ds made cs (readable code, base 0) for a moment: which segment each used
    __asm__ volatile("mov %%cs, %%dx\n mov %%dx, %%ds\n" HERE "1: flds (%%eax)\n mov %%ss, %%dx\n mov %%dx, %%ds"
                     : "=&r"(ip) : "a"(&one) : "edx", "memory");
    data("flds (eax), ds = cs", ip, 0x100, (unsigned long) &one, cs);
    __asm__ volatile("mov %%cs, %%dx\n mov %%dx, %%ds\n push %%eax\n" HERE "1: flds (%%esp)\n add $4, %%esp\n"
                     " mov %%ss, %%dx\n mov %%dx, %%ds" : "=&r"(ip) : "a"(0x3f800000) : "edx", "memory");
    env(); check("flds (esp), ds = cs: fds", e.fds, ss); check("flds (esp): fip", e.fip, ip);
    __asm__ volatile("mov %%cs, %%dx\n mov %%dx, %%ds\n xchg %%ebp, %%eax\n" HERE "1: flds 0(%%ebp)\n"
                     " xchg %%ebp, %%eax\n mov %%ss, %%dx\n mov %%dx, %%ds" : "=&r"(ip) : "a"(&one) : "edx", "memory");
    data("flds 0(ebp), ds = cs", ip, 0x145, (unsigned long) &one, ss);
#endif
    __asm__ volatile("fninit");

    // Register forms leave FIP and FOP, and FDP as it was
    AT("flds " AX, "a"(&one));
    __asm__ volatile("fld1");
    AT0("fadd %%st(0), %%st");                    data("fadd st,st", ip, 0x0c0, (unsigned long) &one, ds);
    AT0("fnop");                                  last("fnop", ip, 0x1d0);
    ip2 = ip;
    // Control insns leave them
    __asm__ volatile("fnstcw %0\n fldcw %0\n fnclex\n fnstsw %%ax\n fwait\n"
                     " .byte 0xdb, 0xe0, 0xdb, 0xe1, 0xdb, 0xe4" : "+m"(two) :: "eax");
    last("after control insns", ip2, 0x1d0);
    AT0("fxch %%st(1)");                          last("fxch", ip, 0x1c9);
    AT0("fincstp");                               last("fincstp", ip, 0x1f7);
    AT0("fdecstp");                               last("fdecstp", ip, 0x1f6);
    AT0("ffree %%st(7)");                         last("ffree", ip, 0x5c7);
    AT0(".byte 0xdf, 0xc7");                      last("ffreep (df c7)", ip, 0x7c7);
    AT0(".byte 0xdd, 0xc8");                      last("fxch4 (dd c8)", ip, 0x5c8);
    AT0(".byte 0xdc, 0xd0");                      last("fcom2 (dc d0)", ip, 0x4d0);
    AT0("fldpi");                                 last("fldpi", ip, 0x1eb);
    AT0("fcomi %%st(1), %%st");                   last("fcomi", ip, 0x3f1);
    AT0("fcmovb %%st(1), %%st");                  last("fcmovb", ip, 0x2c1);
    AT0("fsin");                                  last("fsin", ip, 0x1fe);
    AT0("fstp %%st(0)");                          last("fstp st", ip, 0x5d8);
    data("register forms: fdp kept", ip, 0x5d8, (unsigned long) &one, ds);

    // FXSAVE and XSAVE: zeros with no exception pending
    __asm__ volatile("fxsave %0" : "=m"(*(uint8_t (*)[512]) b));
    check("fxsave, nothing pending: fop", rd16(b + 6), 0);
    check("fxsave, nothing pending: ip", rd64(b + 8), 0);
    check("fxsave, nothing pending: dp", rd64(b + 16), 0);
    memset(b + 512, 0, 64);
    __asm__ volatile("xsave %0" : "+m"(*(uint8_t (*)[1024]) b) : "a"(1), "d"(0));
    check("xsave, nothing pending: ip", rd64(b + 8), 0);

    // ... and while one is: 1/0 with ZE unmasked
    two = 0x37b;
    __asm__ volatile("fninit\n fldcw %0\n fld1" :: "m"(two));
    AT("fdivs " AX, "a"(&fzero));
    __asm__ volatile("fxsave %0" : "=m"(*(uint8_t (*)[512]) b));
    check("fxsave, pending: fop", rd16(b + 6), 0x030);
    check("fxsave, pending: ip", rd64(b + 8), (uint32_t) ip | (uint64_t) cs << 32);
    check("fxsave, pending: dp", rd64(b + 16), (uint32_t) (unsigned long) &fzero | (uint64_t) ds << 32);
    memset(b + 512, 0, 64);
    __asm__ volatile("xsave %0" : "+m"(*(uint8_t (*)[1024]) b) : "a"(1), "d"(0));
    check("xsave, pending: ip", rd64(b + 8), (uint32_t) ip | (uint64_t) cs << 32);
#ifdef __x86_64__
    __asm__ volatile("fxsave64 %0" : "=m"(*(uint8_t (*)[512]) b));
    check("fxsave64, pending: ip", rd64(b + 8), ip);
    check("fxsave64, pending: dp", rd64(b + 16), (unsigned long) &fzero);
    memset(b + 512, 0, 64);
    __asm__ volatile("xsave64 %0" : "+m"(*(uint8_t (*)[1024]) b) : "a"(1), "d"(0));
    check("xsave64, pending: ip", rd64(b + 8), ip);
    check("xsave64, pending: dp", rd64(b + 16), (unsigned long) &fzero);
#endif
    __asm__ volatile("fnclex\n fninit");

    // FXRSTOR loads them, pending or not; then FNSTENV, and FXSAVE once pending
    __asm__ volatile("fninit\n fld1\n fxsave %0" : "=m"(*(uint8_t (*)[512]) (b + 1024)));
    memcpy(b + 1024 + 6, "\x34\x01", 2);
    memcpy(b + 1024 + 8, "\x11\x22\x33\x44\x55\x66\x77\x08", 8);
    memcpy(b + 1024 + 16, "\x99\xaa\xbb\xcc\xdd\xee\xff\x07", 8);
    __asm__ volatile("fxrstor %0" :: "m"(*(uint8_t (*)[512]) (b + 1024)));
    env();
    check("fxrstor: fip", e.fip, 0x44332211); check("fxrstor: fcs", e.fcs, 0x6655);
    check("fxrstor: fop", e.fop, 0x134); check("fxrstor: fdp", e.fdp, 0xccbbaa99);
    check("fxrstor: fds", e.fds, 0xeedd);
    b[1024 + 2] = 0x81; b[1024 + 3] = 0x80; b[1024] = 0x7e;   // IE pending, IM clear
    __asm__ volatile("fxrstor %0\n fxsave %1" :: "m"(*(uint8_t (*)[512]) (b + 1024)), "m"(*(uint8_t (*)[512]) b)
                     : "memory");
    check("fxrstor, pending: fxsave ip", rd64(b + 8), 0x665544332211);
    check("fxrstor, pending: fxsave dp", rd64(b + 16), 0xeeddccbbaa99);
    __asm__ volatile("fnclex\n fninit");
#ifdef __x86_64__
    b[1024 + 2] = 0; b[1024 + 3] = 0; b[1024] = 0x7f;
    __asm__ volatile("fld1\n fxrstor64 %0" :: "m"(*(uint8_t (*)[512]) (b + 1024)));
    env();
    check("fxrstor64: fip", e.fip, 0x44332211); check("fxrstor64: fcs", e.fcs, 0);
    check("fxrstor64: fop", e.fop, 0x134); check("fxrstor64: fdp", e.fdp, 0xccbbaa99);
    check("fxrstor64: fds", e.fds, 0);
    b[1024 + 2] = 0x81; b[1024 + 3] = 0x80; b[1024] = 0x7e;
    __asm__ volatile("fxrstor64 %0\n fxsave64 %1" :: "m"(*(uint8_t (*)[512]) (b + 1024)), "m"(*(uint8_t (*)[512]) b)
                     : "memory");
    check("fxrstor64, pending: fxsave64 ip", rd64(b + 8), 0x0000665544332211);
    check("fxrstor64, pending: fxsave64 dp", rd64(b + 16), 0xffffeeddccbbaa99);
    __asm__ volatile("fnclex\n fninit");
#endif

    // XRSTOR of an initial x87: all zero
    __asm__ volatile("fninit");
    AT("fadds " AX, "a"(&one));
    memset(b + 1024, 0, 1024);
    __asm__ volatile("xrstor %0" :: "m"(*(uint8_t (*)[1024]) (b + 1024)), "a"(1), "d"(0));
    env();
    check("xrstor init: fip", e.fip, 0); check("xrstor init: fcs", e.fcs, 0);
    check("xrstor init: fop", e.fop, 0); check("xrstor init: fdp", e.fdp, 0);

    // The #MF of a pending exception, at the next waiting insn: SIGFPE, whose
    // saved state names the insn that raised it
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_fpe;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigaction(SIGFPE, &sa, NULL);
    two = 0x37b;
    __asm__ volatile("fninit\n fldcw %0\n fld1" :: "m"(two));
    sig = 0;
    if (!sigsetjmp(jb, 1))
        __asm__ volatile(".globl x87_ptrs_mf\nx87_ptrs_mf: fdivs " AX "\n nop\n fwait" :: "a"(&fzero));
    ip = (unsigned long) x87_ptrs_mf;
    check("#MF: SIGFPE", sig, SIGFPE);
    check("#MF: the handler's fip", (uint32_t) s_ip, (uint32_t) ip);
    check("#MF: the handler's fdp", (uint32_t) s_dp, (uint32_t) (unsigned long) &fzero);
#ifdef __x86_64__
    check("#MF: the handler's fip, 64 bits", s_ip, ip);
    check("#MF: the handler's fop", s_op, 0x030);
#else
    // (a 64-bit kernel's 32-bit frame has the process's cs, and no opcode)
    check("#MF: the handler's fcs", s_cs & 0xffff, cs);
#endif
    __asm__ volatile("fnclex\n fninit");

    printf("x87_ptrs: %s (%lu checks, %lu mismatches)\n", bad ? "FAIL" : "PASS", checks, bad);
    return bad != 0;
}
