// Exercises LDXR/STXR (success + retry-on-mismatch) and CAS.
// Uses a stack slot as the shared word under test.
.global _start
.text
_start:
    sub sp, sp, #16              // ADD/SUB-immediate SP-src/dst form
    movz x0, #100
    str x0, [sp]                 // seed the word to 100

    // LDXR/STXR: load-exclusive, store-exclusive should succeed (nothing
    // else touched the word in between) -> x1 (status) should be 0.
    ldxr x2, [sp]                // x2 = 100
    movz x3, #200
    stxr w1, x3, [sp]            // store 200, status -> w1 (0=success)
    cbnz x1, fail                // fail if STXR reported failure

    ldr x4, [sp]                 // should now read back 200
    subs x5, x4, #200
    b.ne fail

    // CAS: expect 200 in x6, swap in 300 via x7. Since memory is still
    // 200, this should succeed: x6 gets the OLD value (200) back, memory
    // becomes 300.
    movz x6, #200
    movz x7, #300
    cas x6, x7, [sp]             // x6 <- old value (200); mem <- 300 if matched
    subs x9, x6, #200            // x6 should be the old value, 200
    b.ne fail

    ldr x10, [sp]                // memory should now be 300
    subs x11, x10, #300
    b.ne fail

    // CAS with a stale expected value should fail (no write), old value
    // returned in x6 (300, not matching our now-wrong expectation of 999).
    movz x6, #999                // wrong expected value
    movz x7, #1                  // new value, should NOT get written
    cas x6, x7, [sp]             // x6 <- actual old value (300)
    subs x12, x6, #300
    b.ne fail

    ldr x13, [sp]                // memory should be unchanged (still 300)
    subs x14, x13, #300
    b.ne fail

    movz x0, #0                  // all good
    movz x8, #93
    svc #0

fail:
    movz x0, #1
    movz x8, #93
    svc #0
