// Exercises Logical (immediate): AND, ORR (incl. the MOV-alias via Rn=XZR),
// EOR, ANDS. Added after real Alpine musl ld.so testing showed this is
// literally the first instruction any real dynamic-linked program executes.
.global _start
.text
_start:
    movz x0, #0xff
    and x0, x0, #0xf        // 0xff & 0xf = 0xf
    subs x1, x0, #0xf
    b.ne fail

    orr x2, xzr, #0x100     // MOV-alias: x2 = 0x100
    subs x3, x2, #0x100
    b.ne fail

    movz x4, #0xff
    eor x4, x4, #0xff       // 0xff ^ 0xff = 0
    cbnz x4, fail

    movz x5, #0xf0
    ands x6, x5, #0xf0      // 0xf0 & 0xf0 = 0xf0, Z should be clear
    b.eq fail               // must NOT be zero
    subs x7, x6, #0xf0
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    movz x0, #1
    movz x8, #93
    svc #0
