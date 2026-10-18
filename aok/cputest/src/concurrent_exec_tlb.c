// concurrent_exec_tlb.c — regression for the stale-TLB use-after-free on
// execve (issue #469: arm64 cargo/rustc SIGILL at pc 0, host SIGSEGV).
//
// The per-thread software TLB survives execve, and the arm64/riscv64 JIT
// frontends re-synced it only by comparing mem change counters. Change ids are
// seeded uniquely per mm but increment locally, so the freed old mm's snapshot
// frequently collided numerically with the new mm's counter; the refresh got
// skipped and the JIT kept translating through the freed struct mm. Outcomes:
// host SIGSEGV (NULL mmu->ops on a zeroed-on-free allocation), guest SIGILL at
// pc 0, or wild accesses through a reused allocation (heap corruption).
//
// Repro: rounds of 8-way concurrent fork+execve of cc1 (any real multi-MB ELF
// works; cc1 is the empirically reliable trigger and is present whenever this
// suite was built — falls back to /bin/sh without it). Concurrency scatters
// the global change-id seed allocation, which lines the counter offsets up the
// way the original cargo -j4 trigger did (~1 in 8 execs collided). On a buggy
// build the emulator itself dies or children get killed by SIGILL/SIGSEGV; a
// fixed build (and real Linux) runs every round to completion with every
// child exiting normally.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include "test_common.h"

#define NPROC 8
#define ROUNDS 32

static int is_true(const char *label, int cond) {
    if (!cond) {
        printf("FAIL %s\n", label);
        failures_total++;
    } else {
        test_logf("ok %s\n", label);
    }
    return cond;
}

// cc1 exits 1 on the bogus flag; that's fine — only a signal death (or the
// emulator dying entirely, which kills this test with it) is a failure.
static char target[512] = "/bin/sh";

// cc1 diagnoses the bogus flag but then falls through to compiling stdin, so it
// only exits promptly if stdin is at EOF. Whatever stdin the suite inherited
// (a terminal, a pipe held open by the launcher, ...) must not leak into the
// exec'd child or every round blocks forever in read() and the parent wedges in
// wait4(). Point fd 0 at /dev/null in the child; close it if that fails so the
// read fails with EBADF rather than hanging. fd 1/2 go to /dev/null as well —
// with stdin at EOF cc1 compiles the empty translation unit and prints a time
// report per exec, which would bury the suite's own output; only the child's
// wait status matters here.
static void child_stdio_to_devnull(void) {
    int fd = open("/dev/null", O_RDWR);
    if (fd < 0) {
        close(STDIN_FILENO);
        return;
    }
    dup2(fd, STDIN_FILENO);
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    if (fd > STDERR_FILENO)
        close(fd);
}

static void find_cc1(void) {
    FILE *p = popen("cc -print-prog-name=cc1 2>/dev/null", "r");
    if (p == NULL)
        return;
    char buf[512];
    if (fgets(buf, sizeof(buf), p) != NULL) {
        buf[strcspn(buf, "\n")] = '\0';
        if (buf[0] == '/' && access(buf, X_OK) == 0)
            strcpy(target, buf);
    }
    pclose(p);
}

int main(int argc, char **argv) {
    test_init(argc, argv);
    find_cc1();
    test_logf("exec target: %s\n", target);
    char cmd[600];
    snprintf(cmd, sizeof(cmd), "exec %s --bogus-arg-for-fast-exit", target);

    for (int round = 0; round < ROUNDS; round++) {
        pid_t pids[NPROC];
        for (int i = 0; i < NPROC; i++) {
            pids[i] = fork();
            if (pids[i] < 0) {
                perror("fork");
                return 2;
            }
            if (pids[i] == 0) {
                // Exec via sh so the triggering exec (sh -> target) starts
                // from a minimal static image: the collision needs the old
                // mm's change counter at exec to land on the new mm's counter
                // at the first post-exec block boundary, and a freshly exec'd
                // `sh -c exec` keeps the old-side counter in the same small
                // band the original repro hit (a suite-built dynamic binary
                // carries a large constant offset and never collides).
                child_stdio_to_devnull();
                execl("/bin/sh", "/bin/sh", "-c", cmd, (char *) NULL);
                _exit(127);
            }
        }
        for (int i = 0; i < NPROC; i++) {
            int status;
            pid_t w;
            while ((w = waitpid(pids[i], &status, 0)) < 0 && errno == EINTR)
                continue;
            if (w != pids[i]) {
                perror("waitpid");
                return 2;
            }
            char label[64];
            snprintf(label, sizeof(label), "round%d.child%d.exited", round, i);
            if (!is_true(label, WIFEXITED(status)) && WIFSIGNALED(status))
                printf("  killed by signal %d\n", WTERMSIG(status));
        }
    }

    return finish_suite("concurrent_exec_tlb");
}
