// Exercises the Phase C part 3 gadget batch: single-register loads/stores
// (immediate/post/pre/register-offset, sign-extending variants), bitfield
// aliases (LSL/LSR imm, UBFX, SXTW, BFI), EXTR/ROR-imm, CSEL/CSET, CCMP,
// MUL/MADD/UDIV/SDIV, CLZ/RBIT/REV, add/subtract extended-register with
// SP (dynamic stack adjustment), MRS/MSR TPIDR_EL0, flag-setting
// shifted-register ops (the store_flags/x17 clobber regression busybox
// caught), and a deliberately page-straddling store/load pair (the
// crosspage write path, otherwise unreachable from aligned code).
// Expected: exits 0. Any other exit code is the number of the first
// failed check, which is more debuggable than a bare 1.
//
// x8 is reserved for the syscall number; x27/x28 hold the check number
// and scratch across checks.
.global _start
.text
_start:
    movz x27, #1              // check number, becomes the exit code on failure

    // 1: STR/LDR unsigned imm + LDRB/LDRSB round trip
    adr x0, buffer
    movz x1, #0x1234
    movk x1, #0x8765, lsl #16
    str x1, [x0, #8]
    ldr x2, [x0, #8]
    cmp x1, x2
    b.ne fail
    add x27, x27, #1          // 2: LDRB zero-extend, LDRSB sign-extend
    movz x3, #0x80
    strb w3, [x0, #3]
    ldrb w4, [x0, #3]
    cmp x4, #0x80
    b.ne fail
    ldrsb x5, [x0, #3]
    cmn x5, #0x80             // sign-extended 0x80 = -128
    b.ne fail

    add x27, x27, #1          // 3: post-index/pre-index writeback
    adr x0, buffer
    movz x1, #0xaa
    str x1, [x0], #8          // post: store at buffer, x0 += 8
    movz x2, #0xbb
    str x2, [x0, #8]!         // pre: x0 += 8, store at buffer+16
    adr x3, buffer
    ldr x4, [x3]
    cmp x4, #0xaa
    b.ne fail
    ldr x5, [x3, #16]
    cmp x5, #0xbb
    b.ne fail
    sub x6, x0, x3            // x0 must have advanced 16 total
    cmp x6, #16
    b.ne fail

    add x27, x27, #1          // 4: register-offset load with LSL shift
    adr x0, buffer
    movz x1, #2
    movz x2, #0xcc
    str x2, [x0, x1, lsl #3]  // buffer + 16
    ldr x3, [x0, x1, lsl #3]
    cmp x3, #0xcc
    b.ne fail

    add x27, x27, #1          // 5: bitfield aliases: LSL/LSR imm, UBFX, SXTW
    movz x0, #1
    lsl x1, x0, #33
    lsr x2, x1, #30
    cmp x2, #8
    b.ne fail
    movz x3, #0xf0f0
    ubfx x4, x3, #4, #8       // bits 11:4 = 0x0f
    cmp x4, #0x0f
    b.ne fail
    movz w5, #0x8000, lsl #16 // w5 = 0x80000000
    sxtw x6, w5               // sign-extends to 0xffffffff80000000
    cmn x6, #1                // != -1, just checking it's negative:
    b.eq fail
    tbz x6, #63, fail         // top bit must be set

    add x27, x27, #1          // 6: BFI (BFM insert, preserves other bits)
    movz x0, #0xffff
    movz x1, #0x5
    bfi x0, x1, #4, #4        // x0 = 0xff5f
    movz x2, #0xff5f
    cmp x0, x2
    b.ne fail

    add x27, x27, #1          // 7: EXTR / ROR immediate
    movz x0, #0xff
    ror x1, x0, #4            // 0xf00000000000000f
    and x2, x1, #0xff
    cmp x2, #0x0f
    b.ne fail

    add x27, x27, #1          // 8: CSEL/CSET
    movz x0, #5
    cmp x0, #5
    cset w1, eq
    cmp w1, #1
    b.ne fail
    csel x2, x0, xzr, ne      // ne is false -> x2 = xzr = 0
    cbnz x2, fail

    add x27, x27, #1          // 9: CCMP (both condition-true and false paths)
    movz x0, #3
    movz x1, #4
    cmp x0, #3                // Z=1
    ccmp x1, #4, #0, eq       // eq true -> flags from (x1-4): Z=1
    b.ne fail
    cmp x0, #99               // Z=0
    ccmp x1, #17, #0, eq      // eq false -> flags = 0 (Z=0)
    b.eq fail

    add x27, x27, #1          // 10: MUL/MADD/UDIV/SDIV
    movz x0, #7
    movz x1, #6
    mul x2, x0, x1
    cmp x2, #42
    b.ne fail
    movz x3, #100
    udiv x4, x3, x0           // 100/7 = 14
    cmp x4, #14
    b.ne fail
    mov x5, #-100
    sdiv x6, x5, x0           // -100/7 = -14 (round toward zero)
    cmn x6, #14
    b.ne fail
    madd x7, x0, x1, x3       // 7*6+100 = 142
    movz x9, #142
    cmp x7, x9
    b.ne fail

    add x27, x27, #1          // 11: CLZ/RBIT/REV
    movz x0, #1, lsl #16      // bit 16 set
    clz x1, x0
    cmp x1, #47
    b.ne fail
    movz x2, #1
    rbit x3, x2               // bit 0 -> bit 63
    tbz x3, #63, fail
    movz x4, #0x1122
    movk x4, #0x3344, lsl #16
    rev w5, w4                // 0x33441122 -> 0x22114433
    movz x6, #0x4433
    movk x6, #0x2211, lsl #16
    cmp w5, w6
    b.ne fail

    add x27, x27, #1          // 12: extended-register sub/add on SP
    mov x0, sp
    movz x1, #32
    sub sp, sp, x1            // addsub_ext, Rd=Rn=SP
    mov x2, sp
    sub x3, x0, x2
    cmp x3, #32
    b.ne fail
    add sp, sp, x1            // restore
    mov x4, sp
    cmp x4, x0
    b.ne fail

    add x27, x27, #1          // 13: MRS/MSR TPIDR_EL0
    movz x0, #0xbeef
    msr tpidr_el0, x0
    mrs x1, tpidr_el0
    cmp x1, x0
    b.ne fail

    add x27, x27, #1          // 14: flag-setting shifted-register (the
                              // store_flags/x17 regression) — ANDS and SUBS
    movz x0, #0xf0
    ands x1, x0, x0, lsr #4   // 0xf0 & 0x0f = 0, Z set
    b.ne fail
    cbnz x1, fail
    movz x2, #10
    subs x3, x2, x2, lsl #1   // 10 - 20 = -10, N set
    b.pl fail
    cmn x3, #10
    b.ne fail

    add x27, x27, #1          // 15: page-straddling store/load (crosspage
                              // write fill+flush path; buffer spans two pages)
    adr x0, straddle          // 4 bytes before a page boundary
    movz x1, #0x1111
    movk x1, #0x2222, lsl #16
    movk x1, #0x3333, lsl #32
    movk x1, #0x4444, lsl #48
    str x1, [x0]              // 8-byte store, 4 bytes in each page
    ldr x2, [x0]              // 8-byte crosspage load back
    cmp x1, x2
    b.ne fail
    ldr w3, [x0, #4]          // aligned read of the second half
    movz x4, #0x3333
    movk x4, #0x4444, lsl #16
    cmp w3, w4
    b.ne fail

    movz x0, #0
    movz x8, #93
    svc #0

fail:
    mov x0, x27
    movz x8, #93
    svc #0

.bss
.balign 4096
buffer:
    .skip 4092
straddle:                     // last 4 bytes of this page — an 8-byte access here straddles
    .skip 4100
