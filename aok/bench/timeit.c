// timeit NAME CMD [ARGS...] -- run CMD, print "RESULT NAME wall_ms user_ms sys_ms status".
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/resource.h>
static double ms(struct timeval tv) { return tv.tv_sec * 1e3 + tv.tv_usec / 1e3; }
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    pid_t pid = fork();
    if (pid == 0) {
        int nul = open("/dev/null", O_WRONLY);
        if (nul >= 0) dup2(nul, 1);
        execvp(argv[2], argv + 2);
        _exit(127);
    }
    int st; struct rusage ru;
    wait4(pid, &st, 0, &ru);
    clock_gettime(CLOCK_MONOTONIC, &b);
    double wall = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
    printf("RESULT %s %.0f %.0f %.0f %d\n", argv[1], wall, ms(ru.ru_utime), ms(ru.ru_stime),
           WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st));
    fflush(stdout);
    return 0;
}
