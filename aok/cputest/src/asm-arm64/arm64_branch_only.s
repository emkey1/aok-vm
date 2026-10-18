// Exercises B, CBZ (taken), CBNZ (not taken), BL/RET -- no memory
// instructions at all, since STP/LDR/etc aren't ported to gadgets yet.
.global _start
.text
_start:
    movz x0, #5
    b skip_this
    movz x0, #99        // must be skipped

skip_this:
    movz x1, #0
    cbz x1, take_it
    movz x0, #99         // must be skipped (cbz should be taken, x1==0)
take_it:
    movz x2, #1
    cbnz x2, take_it2
    movz x0, #99          // must be skipped (cbnz should be taken, x2!=0)
take_it2:
    bl subroutine
    b after

subroutine:
    movz x3, #7
    ret

after:
    // x0 should still be 5 (never overwritten by the skipped movz #99s)
    movz x8, #93
    svc #0
