// Exercises Data-Processing (register): Logical (shifted register)
// including the MOV(register) alias, and Add/subtract (shifted register)
// including shifted operands. Added for the JIT gadget port's Phase C
// part 2 (jit/guest-arm64/dpreg.S) -- these are the confirmed next
// blocker for any real dynamic-linked userland (patch 5's real-rootfs
// testing), immediately after Logical (immediate).
//
// Avoids x8 as a data register throughout (reserved for the syscall
// number ahead of `svc #0`, per arm64_hello.s's convention).
.global _start
.text
_start:
    movz x0, #5
    mov x1, x0              // MOV (register) alias = ORR(shifted-reg, Rn=XZR, shift=0)
    subs x2, x1, #5
    b.ne fail

    movz x3, #1
    add x4, x3, x3, lsl #4  // 1 + (1<<4) = 17
    subs x5, x4, #17
    b.ne fail

    movz x6, #0xff
    and x7, x6, x6, lsr #4  // 0xff & 0x0f = 0xf
    subs x9, x7, #0xf
    b.ne fail

    movz x10, #0x10
    sub x11, x10, x10, lsr #4 // 0x10 - 1 = 0xf
    subs x12, x11, #0xf
    b.ne fail

    orr x13, xzr, x6, ror #4  // ROR(0xff, 4): low byte should come back as 0xf
    and x14, x13, #0xff
    subs x15, x14, #0xf
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    movz x0, #1
    movz x8, #93
    svc #0
