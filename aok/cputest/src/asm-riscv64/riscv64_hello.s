.global _start
_start:
    li a7, 64          # write
    li a0, 1
    lla a1, msg
    li a2, 14
    ecall
    li a7, 93          # exit
    li a0, 0
    ecall
.section .rodata
msg: .ascii "hello riscv64\n"
