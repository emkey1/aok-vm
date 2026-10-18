// Scalar Advanced-SIMD fixed-point convert (AdvSIMD scalar shift by
// immediate, opcodes 0x1c/0x1f): UCVTF/SCVTF and FCVTZS/FCVTZU Dd, Dn,
// #fbits. This is the instruction family that SIGILL'd rtorrent's MSE
// Diffie-Hellman/SHA-1 path on the aarch64 guest port: encoding
// 0x7f6ce442 disassembles to `ucvtf d2, d2, #0x14` (fbits=20), and the
// "AdvSIMD scalar shift by immediate, remaining opcodes" decode in
// jit/gen.c had every opcode in this instruction class handled *except*
// 0x1c/0x1f, so it fell through to gen_arm64_undefined_at(). Checks 1-9
// cover SCVTF/UCVTF (0x1c, the reported crash); 10-13 cover the sibling
// FCVTZS/FCVTZU (0x1f), closed proactively since it shares the exact
// same gadget infrastructure and was equally unhandled.
//
// Expected result bit patterns below were captured by running the
// identical instructions natively on the host arm64 CPU (not through
// ish) via the scratch programs native_ucvtf.c/native_fcvtz.c, so this
// is a genuine hardware cross-check, not just internal self-consistency.
// Expected: exits 0; non-zero exit = number of the first failed check.
.global _start
.text
_start:
    movz x27, #1              // 1: UCVTF, in=0 -> 0.0
    movz x0, #0
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    cmp x1, #0
    b.ne fail

    add x27, x27, #1          // 2: UCVTF, in=1 -> 0x3eb0000000000000
    movz x0, #1
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0x3eb0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 3: UCVTF, in=0x100000 -> 1.0 (0x3ff0000000000000)
    movz x0, #0x10, lsl #16
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x3ff0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 4: UCVTF, in=all-ones -> 0x42b0000000000000
    movn x0, #0
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x42b0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 5: SCVTF, in=all-ones (i.e. -1) -> 0xbeb0000000000000
    movn x0, #0
    fmov d2, x0
    scvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0xbeb0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 6: UCVTF, in=0x123456789abcdef0 -> 0x42723456789abcdf
    movz x0, #0xdef0
    movk x0, #0x9abc, lsl #16
    movk x0, #0x5678, lsl #32
    movk x0, #0x1234, lsl #48
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0xbcdf
    movk x2, #0x789a, lsl #16
    movk x2, #0x3456, lsl #32
    movk x2, #0x4272, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 7: SCVTF, same bits (as signed, positive) -> same 0x42723456789abcdf
    movz x0, #0xdef0
    movk x0, #0x9abc, lsl #16
    movk x0, #0x5678, lsl #32
    movk x0, #0x1234, lsl #48
    fmov d2, x0
    scvtf d2, d2, #0x14
    fmov x1, d2
    cmp x1, x2                          // x2 still holds expected from check 6
    b.ne fail

    add x27, x27, #1          // 8: UCVTF, in=0x8000000000000000 -> 0x42a0000000000000
    movz x0, #0x8000, lsl #48
    fmov d2, x0
    ucvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x42a0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 9: SCVTF, in=0x8000000000000000 (i.e. INT64_MIN) -> 0xc2a0000000000000
    movz x0, #0x8000, lsl #48
    fmov d2, x0
    scvtf d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0xc2a0, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 10: FCVTZU, in=1.0 (0x3ff0...) -> 0x0000000000100000
    movz x0, #0x3ff0, lsl #48
    fmov d2, x0
    fcvtzu d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x10, lsl #16
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 11: FCVTZS, in=-1.0 (0xbff0...) -> 0xfffffffffff00000
    movz x0, #0xbff0, lsl #48
    fmov d2, x0
    fcvtzs d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0xfff0, lsl #16
    movk x2, #0xffff, lsl #32
    movk x2, #0xffff, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 12: FCVTZU, in=1234.5 (0x40934a00...) -> 0x000000004d280000
    movz x0, #0x4a00, lsl #32
    movk x0, #0x4093, lsl #48
    fmov d2, x0
    fcvtzu d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x4d28, lsl #16
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 13: FCVTZS, in=-1234.5 (0xc0934a00...) -> 0xffffffffb2d80000
    movz x0, #0x4a00, lsl #32
    movk x0, #0xc093, lsl #48
    fmov d2, x0
    fcvtzs d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0xb2d8, lsl #16
    movk x2, #0xffff, lsl #32
    movk x2, #0xffff, lsl #48
    cmp x1, x2
    b.ne fail

    add x27, x27, #1          // 14: FCVTZU, in=1e9 (0x41cdcd65...) -> 0x0003b9aca0000000
    movz x0, #0xcd65, lsl #32
    movk x0, #0x41cd, lsl #48
    fmov d2, x0
    fcvtzu d2, d2, #0x14
    fmov x1, d2
    movz x2, #0x0000
    movk x2, #0xa000, lsl #16
    movk x2, #0xb9ac, lsl #32
    movk x2, #0x0003, lsl #48
    cmp x1, x2
    b.ne fail

    // ---- S (32-bit) scalar forms: an earlier D-only version of this fix
    // would SIGILL right here — 0x7f36e442 (ucvtf s2, s2, #0xa) is the
    // same instruction family, one bit (immh) away from the D-form crash.
    add x27, x27, #1          // 15: UCVTF (S), in=1 -> 0x3a800000
    movz w0, #1
    fmov s2, w0
    ucvtf s2, s2, #0xa
    fmov w1, s2
    movz w2, #0x3a80, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 16: UCVTF (S), in=0x400 -> 1.0f (0x3f800000)
    movz w0, #0x400
    fmov s2, w0
    ucvtf s2, s2, #0xa
    fmov w1, s2
    movz w2, #0x3f80, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 17: UCVTF (S), in=all-ones -> 0x4a800000
    movn w0, #0
    fmov s2, w0
    ucvtf s2, s2, #0xa
    fmov w1, s2
    movz w2, #0x4a80, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 18: SCVTF (S), in=all-ones (-1) -> 0xba800000
    fmov s2, w0                // w0 still all-ones from check 17
    scvtf s2, s2, #0xa
    fmov w1, s2
    movz w2, #0xba80, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 19: UCVTF (S), in=0x12345678 -> 0x4891a2b4
    movz w0, #0x5678
    movk w0, #0x1234, lsl #16
    fmov s2, w0
    ucvtf s2, s2, #0xa
    fmov w1, s2
    movz w2, #0xa2b4
    movk w2, #0x4891, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 20: FCVTZU (S), in=1234.5f (0x449a5000) -> 0x00134a00
    movz w0, #0x5000
    movk w0, #0x449a, lsl #16
    fmov s2, w0
    fcvtzu s2, s2, #0xa
    fmov w1, s2
    movz w2, #0x4a00
    movk w2, #0x0013, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 21: FCVTZS (S), in=-1234.5f (0xc49a5000) -> 0xffecb600
    movz w0, #0x5000
    movk w0, #0xc49a, lsl #16
    fmov s2, w0
    fcvtzs s2, s2, #0xa
    fmov w1, s2
    movz w2, #0xb600
    movk w2, #0xffec, lsl #16
    cmp w1, w2
    b.ne fail

    add x27, x27, #1          // 22: FCVTZS (S), in=-1.0f (0xbf800000) -> 0xfffffc00
    movz w0, #0x0000
    movk w0, #0xbf80, lsl #16
    fmov s2, w0
    fcvtzs s2, s2, #0xa
    fmov w1, s2
    movz w2, #0xfc00
    movk w2, #0xffff, lsl #16
    cmp w1, w2
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    mov x0, x27
    movz x8, #93
    svc #0
