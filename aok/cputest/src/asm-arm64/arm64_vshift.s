// AdvSIMD vector shift-by-immediate: UXTL/USHLL/SSHLL (widen), SSHR/USHR
// (arithmetic/logical right), SHL. Added after Alpine getty crash-looped
// on-device on `ushll v31.2d, v31.2s, #0` (the UXTL alias) — init
// respawning getty made the failure a boot-blocking loop. Expected:
// exits 0; non-zero = number of the first failed check.
.global _start
.text
_start:
    movz x27, #1              // 1: UXTL (ushll #0): 2x32 -> 2x64
    movz x0, #1
    movk x0, #2, lsl #32      // x0 = 0x00000002_00000001 = v0.2s = {1, 2}
    fmov d0, x0
    uxtl v1.2d, v0.2s
    fmov x1, d1               // lane 0
    cmp x1, #1
    b.ne fail
    mov x2, v1.d[1]           // lane 1
    cmp x2, #2
    b.ne fail

    add x27, x27, #1          // 2: USHLL #4: {1,2} -> {16,32}
    ushll v2.2d, v0.2s, #4
    fmov x3, d2
    cmp x3, #16
    b.ne fail
    mov x4, v2.d[1]
    cmp x4, #32
    b.ne fail

    add x27, x27, #1          // 3: SSHLL on negative: {-1 as s32} -> sign-extended
    movn w5, #0               // 0xffffffff
    fmov s3, w5               // v3.2s = {-1, 0}
    sshll v4.2d, v3.2s, #0
    fmov x6, d4
    cmn x6, #1                // == -1 (64-bit)
    b.ne fail

    add x27, x27, #1          // 4: SSHR arithmetic right: 0x80000000 >> 1 = 0xC0000000
    movz w7, #0x8000, lsl #16
    fmov s5, w7
    sshr v6.2s, v5.2s, #1
    mov w9, v6.s[0]
    movz w10, #0xC000, lsl #16
    cmp w9, w10
    b.ne fail

    add x27, x27, #1          // 5: USHR logical right: 0x80000000 >> 1 = 0x40000000
    ushr v7.2s, v5.2s, #1
    mov w11, v7.s[0]
    movz w12, #0x4000, lsl #16
    cmp w11, w12
    b.ne fail

    add x27, x27, #1          // 6: SHL: 1 << 7 = 128 per byte lane
    movi v8.8b, #1
    shl v9.8b, v8.8b, #7
    umov w13, v9.b[0]
    cmp w13, #128
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0
fail:
    mov x0, x27
    movz x8, #93
    svc #0
