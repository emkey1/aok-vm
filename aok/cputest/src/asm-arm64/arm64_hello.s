// Minimal static AArch64 test: write("hi\n") then exit(42).
// Exercises: ADR (string address), MOVZ (syscall numbers/fd/len/exit code),
// SVC (syscall entry), and the function-call-free straight-line path.
.global _start
.text
_start:
    // write(1, msg, 3)
    movz x0, #1        // fd = stdout
    adr  x1, msg        // buf
    movz x2, #3         // count
    movz x8, #64        // __NR_write (aarch64)
    svc  #0

    // exit(42)
    movz x0, #42
    movz x8, #93        // __NR_exit
    svc  #0

msg:
    .ascii "hi\n"
