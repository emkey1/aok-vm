// Signal delivery + rt_sigreturn round trip, mimicking the busybox-sh
// SIGCHLD flow that first exercised the arm64 signal path: install a
// handler with rt_sigaction, raise the signal via kill(getpid(), sig),
// verify the handler ran (it writes a marker), verify registers survive
// the delivery/sigreturn round trip, then run the musl __errno_location
// pattern (mrs tpidr after a bl, with x0 previously -1) that the
// original crash implicated. Expected: exits 0; non-zero exit = number
// of the first failed check.
.global _start
.text

handler:
    adr x9, marker
    movz w10, #0x5a
    strb w10, [x9]
    ret                        // returns to the on-stack sigreturn trampoline

errno_like:
    mrs x0, tpidr_el0
    sub x0, x0, #0xa4
    ret

_start:
    movz x27, #1

    // TLS base for the errno_like probe later: point it at a writable
    // spot well inside the buffer (so base-0xa4 stays writable too)
    adr x0, buffer
    add x0, x0, #0x200
    msr tpidr_el0, x0

    // 1: rt_sigaction(SIGUSR1=10, &act, NULL, 8)
    adr x1, sigact
    adr x2, handler
    str x2, [x1]               // sa_handler
    str xzr, [x1, #8]          // sa_flags = 0
    str xzr, [x1, #16]         // sa_restorer = 0
    str xzr, [x1, #24]         // sa_mask = 0
    movz x0, #10               // SIGUSR1
    mov x2, #0
    movz x3, #8                // sigsetsize
    movz x8, #134              // rt_sigaction
    svc #0
    cbnz x0, fail

    add x27, x27, #1           // 2: getpid + kill(self, SIGUSR1); registers
                               // x20-x22 must survive delivery + sigreturn
    movz x20, #0x1111
    movz x21, #0x2222
    movz x22, #0x3333
    movz x8, #172              // getpid
    svc #0
    movz x8, #129              // kill
    movz x1, #10
    svc #0
    cbnz x0, fail

    add x27, x27, #1           // 3: handler ran (marker set)
    adr x9, marker
    ldrb w10, [x9]
    cmp w10, #0x5a
    b.ne fail

    add x27, x27, #1           // 4: callee-ish registers survived
    movz x9, #0x1111
    cmp x20, x9
    b.ne fail
    movz x9, #0x2222
    cmp x21, x9
    b.ne fail
    movz x9, #0x3333
    cmp x22, x9
    b.ne fail

    add x27, x27, #1           // 5: the busybox crash pattern: x0=-1,
                               // bl to an mrs-tpidr function, store through
                               // the result
    movn x0, #0                // x0 = -1
    bl errno_like
    movz w2, #10
    str w2, [x0]               // errno-style store; faults if x0 is junk
    ldr w3, [x0]
    cmp w3, #10
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    mov x0, x27
    movz x8, #93
    svc #0

.data
.balign 16
sigact:
    .skip 32
marker:
    .skip 16
.balign 16
buffer:
    .skip 1024
