// AdvSIMD LD1/ST1 (load/store multiple, contiguous): 1- and 2-register
// loads, post-index-immediate writeback, and ST1. musl getcwd/string ops
// use these (`cd /AOK` crash-looped on-device: `ld1 {v30.16b,v31.16b}`).
// Expected: exits 0; non-zero = number of the first failed check.
.global _start
.text
_start:
    movz x27, #1
    // fill 32 bytes at buf with a known pattern: byte i = i
    adr x0, buf
    movz x1, #0
1:  strb w1, [x0, x1]
    add x1, x1, #1
    cmp x1, #32
    b.ne 1b

    // LD1 {v0.16b, v1.16b}, [x0]  — load 32 bytes into v0,v1
    ld1 {v0.16b, v1.16b}, [x0]
    // v0.b[0] should be 0, v0.b[15]=15, v1.b[0]=16, v1.b[15]=31
    umov w2, v0.b[0]
    cbnz w2, fail
    add x27, x27, #1
    umov w2, v0.b[15]
    cmp w2, #15
    b.ne fail
    add x27, x27, #1
    umov w2, v1.b[0]
    cmp w2, #16
    b.ne fail
    add x27, x27, #1
    umov w2, v1.b[15]
    cmp w2, #31
    b.ne fail

    add x27, x27, #1           // LD1 single reg {v2.16b}
    ld1 {v2.16b}, [x0]
    umov w2, v2.b[7]
    cmp w2, #7
    b.ne fail

    add x27, x27, #1           // LD1 post-index by immediate: {v3.16b},[x0],#16
    adr x0, buf
    ld1 {v3.16b}, [x0], #16
    adr x3, buf
    add x3, x3, #16
    cmp x0, x3                 // x0 advanced by 16
    b.ne fail
    umov w2, v3.b[3]
    cmp w2, #3
    b.ne fail

    add x27, x27, #1           // ST1 {v0.16b},[buf2] then compare
    adr x4, buf2
    st1 {v0.16b}, [x4]
    ldrb w2, [x4, #10]
    cmp w2, #10
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
buf:  .skip 32
buf2: .skip 16
