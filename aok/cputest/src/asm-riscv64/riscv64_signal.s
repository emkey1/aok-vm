.global _start
_start:
    lla t0, handler        # rt_sigaction(SIGUSR1=10, &act, 0, 8)
    lla t1, act
    sd t0, 0(t1)           # sa_handler
    li a7, 134
    li a0, 10
    mv a1, t1
    li a2, 0
    li a3, 8
    ecall
    bnez a0, fail
    li a7, 172             # getpid
    ecall
    mv t2, a0
    li a7, 129             # kill(pid, SIGUSR1)
    mv a0, t2
    li a1, 10
    ecall
    lla t3, gotsig         # handler must have run by now
    ld t4, 0(t3)
    li t5, 42
    bne t4, t5, fail
    li a0, 0
    j done
handler:
    lla t6, gotsig
    li t5, 42
    sd t5, 0(t6)
    ret                    # returns to the on-stack trampoline -> rt_sigreturn
fail:
    li a0, 1
done:
    li a7, 93
    ecall
.data
.balign 8
act:    .space 32          # handler, flags, restorer, mask
gotsig: .dword 0
