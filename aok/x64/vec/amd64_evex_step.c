// AVX-512 under a debugger's single step: PTRACE_SINGLESTEP (EFLAGS.TF)
// through EVEX and opmask instructions, a masked store and load among them.
// AOK VM's own (not iSH-AOK's). TCG has no AVX-512, so a stepped TB of one
// of these is the AOK translator's, of that insn alone with the step's #DB
// after it: each instruction must stop once, none may raise #UD (SIGILL),
// and the results must be the ones the unstepped run gets.
#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

// step_body(out): nine instructions, then the ret at step_end.
extern void step_body(uint32_t *out);
extern char step_end[];
__asm__(".text\n.globl step_body\nstep_body:\n"
        "vpternlogd $0xff, %zmm0, %zmm0, %zmm0\n"     // zmm0 all ones
        "vpaddd %zmm0, %zmm0, %zmm1\n"                // zmm1 dwords 0xfffffffe
        "movl $0x5555, %eax\n"
        "kmovw %eax, %k1\n"                           // the even dwords
        "vmovdqu32 %zmm1, (%rdi){%k1}\n"              // out[even] = 0xfffffffe
        "vpxord %zmm2, %zmm2, %zmm2\n"
        "vmovdqu32 (%rdi), %zmm2{%k1}{z}\n"           // even 0xfffffffe, odd 0
        "vpaddd %zmm2, %zmm1, %zmm3\n"                // even 0xfffffffc, odd 0xfffffffe
        "vmovdqu64 %zmm3, 64(%rdi)\n"
        ".globl step_end\nstep_end:\n"
        "ret\n");
#define BODY_STOPS 10   // after the call, and after each of the nine

static int check(const uint32_t *out)
{
    for (int i = 0; i < 16; i++) {
        uint32_t lo = i & 1 ? 0x11111111 : 0xfffffffe, hi = i & 1 ? 0xfffffffe : 0xfffffffc;
        if (out[i] != lo || out[16 + i] != hi)
            return 0;
    }
    return 1;
}

int main(void)
{
    uint32_t a, b, c, d;
    __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(7), "c"(0));
    if (!(b & (1u << 16))) {
        printf("amd64_evex_step: PASS (no AVX-512 here: nothing to step)\n");
        return 0;
    }
    static uint32_t ref[32];
    memset(ref, 0x11, sizeof(ref));
    step_body(ref);
    if (!check(ref)) {
        printf("amd64_evex_step: FAIL (unstepped run's results wrong)\n");
        return 1;
    }

    pid_t pid = fork();
    if (pid == 0) {
        static uint32_t out[32];
        memset(out, 0x11, sizeof(out));
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        step_body(out);
        _exit(check(out) ? 0 : 3);
    }
    int st, stops = 0, body = 0;
    waitpid(pid, &st, 0);
    for (;;) {
        if (ptrace(PTRACE_SINGLESTEP, pid, 0, 0) != 0)
            break;
        waitpid(pid, &st, 0);
        if (WIFEXITED(st) || WIFSIGNALED(st))
            break;
        if (WSTOPSIG(st) != SIGTRAP) {
            struct user_regs_struct r;
            ptrace(PTRACE_GETREGS, pid, 0, &r);
            printf("amd64_evex_step: FAIL (signal %d at %#llx, %d into the body)\n", WSTOPSIG(st),
                   (unsigned long long) r.rip, body);
            kill(pid, SIGKILL);
            return 1;
        }
        struct user_regs_struct r;
        ptrace(PTRACE_GETREGS, pid, 0, &r);
        if (r.rip >= (uintptr_t) step_body && r.rip <= (uintptr_t) step_end)
            body++;
        if (++stops > 2000000)
            break;
    }
    int ok = WIFEXITED(st) && WEXITSTATUS(st) == 0 && body == BODY_STOPS;
    printf("amd64_evex_step: %s (%d stops, %d of them in the body of %d; child %s %d)\n", ok ? "PASS" : "FAIL",
           stops, body, BODY_STOPS, WIFEXITED(st) ? "exit" : "signal", WIFEXITED(st) ? WEXITSTATUS(st) : WTERMSIG(st));
    return !ok;
}
