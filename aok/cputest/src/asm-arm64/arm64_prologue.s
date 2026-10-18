// Exercises: function prologue/epilogue (STP/LDP pre/post-index), BL/RET,
// ADD/SUB immediate (with and without flags), B.cond, CBZ. Deliberately
// avoids register-form ADD/SUB (add x0,x0,x1) since that's DP_REG, a
// documented patch-3 scope cut (INT_UNDEFINED, not yet implemented).
.global _start
.text

addfive:
    stp x29, x30, [sp, #-16]!   // prologue
    mov x29, sp                 // ADD X29, SP, #0 -- immediate form, supported
    add x0, x0, #5               // ADD-immediate
    ldp x29, x30, [sp], #16     // epilogue
    ret

_start:
    movz x0, #4
    bl addfive                  // x0 = 4+5 = 9

    subs x3, x0, #9             // compare result to 9 -- sets flags
    b.eq good
    movz x0, #1                 // wrong result
    movz x8, #93
    svc #0

good:
    cbz x3, really_good         // x3 should be 0 from the SUBS above
    movz x0, #1
    movz x8, #93
    svc #0

really_good:
    movz x0, #0
    movz x8, #93                // exit(0)
    svc #0
