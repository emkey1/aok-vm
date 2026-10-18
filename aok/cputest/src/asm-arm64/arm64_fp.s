// Scalar floating-point smoke test: FMOV-imm, arithmetic, FCMP+B.cond,
// FCSEL (including the w10-handoff regression: the fcsel gadget once
// parsed its rn field into the register carrying the condition result,
// silently turning every select into "rn != v0" — musl's atan returned
// -atan(x) for every input), FNEG/FABS/FSQRT, SCVTF/FCVTZS round trips,
// FMADD, and the scalar SHL-by-immediate strtod uses. Expected: exits 0;
// non-zero exit = number of the first failed check.
.global _start
.text
_start:
    movz x27, #1              // 1: FMOV imm + FADD + FCMP
    fmov d0, #1.0
    fmov d1, #0.5
    fadd d2, d0, d1           // 1.5
    fmov d3, #1.5
    fcmp d2, d3
    b.ne fail

    add x27, x27, #1          // 2: FSUB order + FCMP #0.0
    fsub d4, d0, d1           // 1.0 - 0.5 = 0.5
    fcmp d4, d1
    b.ne fail
    fsub d5, d4, d1           // 0.0
    fcmp d5, #0.0
    b.ne fail

    add x27, x27, #1          // 3: FMUL/FDIV
    fmov d6, #4.0
    fmul d7, d6, d1           // 2.0
    fmov d8, #2.0
    fcmp d7, d8
    b.ne fail
    fdiv d9, d6, d8           // 2.0
    fcmp d9, d8
    b.ne fail

    add x27, x27, #1          // 4: FCSEL both senses (the w10 regression)
    fcmp d0, d0               // 1.0 == 1.0: Z set
    fcsel d10, d8, d1, eq     // eq true -> d8 (2.0)
    fcmp d10, d8
    b.ne fail
    fcsel d11, d8, d1, ne     // ne false -> d1 (0.5)
    fcmp d11, d1
    b.ne fail

    add x27, x27, #1          // 5: FNEG/FABS
    fneg d12, d0              // -1.0
    fcmp d12, d0
    b.eq fail
    fabs d13, d12             // 1.0
    fcmp d13, d0
    b.ne fail

    add x27, x27, #1          // 6: FSQRT
    fsqrt d14, d6             // sqrt(4) = 2
    fcmp d14, d8
    b.ne fail

    add x27, x27, #1          // 7: SCVTF / FCVTZS round trip (incl. negative)
    movn x0, #41              // -42
    scvtf d15, x0
    fcvtzs x1, d15
    cmn x1, #42
    b.ne fail
    movz w2, #123
    scvtf s16, w2
    fcvtzs w3, s16
    cmp w3, #123
    b.ne fail

    add x27, x27, #1          // 8: FMADD (2*3+4 = 10) and FMSUB (4-2*3 = -2)
    fmov d17, #3.0
    fmadd d18, d8, d17, d6    // 2*3+4 = 10
    fmov d19, #10.0
    fcmp d18, d19
    b.ne fail
    fmsub d20, d8, d17, d6    // 4 - 2*3 = -2
    fneg d21, d8
    fcmp d20, d21
    b.ne fail

    add x27, x27, #1          // 9: FCVT S<->D
    fmov s22, #1.5
    fcvt d23, s22
    fcmp d23, d2              // 1.5 (computed in check 1)
    b.ne fail

    add x27, x27, #1          // 10: scalar SHL #52 builds 1.0's exponent (strtod)
    movz x4, #0x3ff
    fmov d24, x4              // low bits = 0x3ff
    shl d24, d24, #52         // 0x3ff0000000000000 = 1.0
    fcmp d24, d0
    b.ne fail

    add x27, x27, #1          // 11: FCCMP: eq true -> compare, else nzcv
    fcmp d0, d0               // Z=1
    fccmp d8, d8, #0, eq      // eq -> fcmp(2,2): Z=1
    b.ne fail
    fcmp d0, d8               // Z=0 (1 != 2)
    fccmp d8, d8, #0, eq      // eq false -> nzcv=0 -> Z=0
    b.eq fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    mov x0, x27
    movz x8, #93
    svc #0
