// Exercises CBZ/CBNZ not-taken paths, B.cond taken and not-taken, BR, TBZ/TBNZ.
.global _start
.text
_start:
    // CBZ not-taken (x1=5, nonzero -> falls through)
    movz x1, #5
    cbz x1, fail
    // CBNZ not-taken (x2=0 -> falls through)
    movz x2, #0
    cbnz x2, fail

    // TBZ: bit 0 of x5 (=0b10, bit0=0) should be zero -> taken
    movz x5, #2
    tbz x5, #0, tbz_ok
    b fail

tbz_ok:
    // TBNZ: bit 1 of x5 (=0b10, bit1=1) should be set -> taken
    tbnz x5, #1, tbnz_ok
    b fail

tbnz_ok:
    // BR: branch to a register-held address
    adr x6, br_target
    br x6
    b fail

br_target:
    movz x0, #0        // success
    movz x8, #93
    svc #0

fail:
    movz x0, #1        // failure
    movz x8, #93
    svc #0
