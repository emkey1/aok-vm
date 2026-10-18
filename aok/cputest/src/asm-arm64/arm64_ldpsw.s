// LDPSW (load pair of signed words, opc=01 in the LDP/STP encoding):
// two 32-bit loads each sign-extended to 64 bits. busybox su/login hit
// this during NSS group setup; it was decoded as "unallocated" before.
// Expected: exits 0; non-zero = number of the first failed check.
.global _start
.text
_start:
    movz x27, #1              // store two words: -1 and +2, then LDPSW them back
    adr x0, buf
    movn w1, #0              // 0xffffffff (= -1 as signed word)
    movz w2, #2
    str w1, [x0]
    str w2, [x0, #4]
    ldpsw x3, x4, [x0]       // x3 = sext(-1) = -1, x4 = sext(2) = 2
    cmn x3, #1              // x3 == -1 ?
    b.ne fail

    add x27, x27, #1
    cmp x4, #2              // x4 == 2 ?
    b.ne fail

    add x27, x27, #1        // pre-index writeback form
    adr x0, buf
    movz w5, #0x8000, lsl #16 // 0x80000000 = most-negative signed word
    str w5, [x0, #8]
    movz w6, #7
    str w6, [x0, #12]
    ldpsw x7, x9, [x0, #8]!  // x0 now buf+8; x7 = sext(0x80000000), x9 = 7
    movz x10, #0x8000, lsl #16
    orr x10, x10, #0xffffffff00000000  // 0xffffffff80000000
    cmp x7, x10
    b.ne fail
    cmp x9, #7
    b.ne fail
    adr x11, buf
    add x11, x11, #8
    cmp x0, x11             // writeback landed
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
buf:
    .skip 32
