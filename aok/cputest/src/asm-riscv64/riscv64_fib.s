.global _start
_start:
    li t0, 0           # fib(0)
    li t1, 1           # fib(1)
    li t2, 20          # count
loop:
    add t3, t0, t1
    mv t0, t1
    mv t1, t3
    addi t2, t2, -1
    bnez t2, loop
    # after 20 iterations t0=fib(20)=6765; exercises div/rem/mul
    li t4, 100
    divu t5, t0, t4    # 6765/100 = 67
    remu t6, t0, t4    # 65
    mul a0, t5, t6     # 67*65 = 4355; 4355 & 0xff = 3
    andi a0, a0, 0xff
    li a7, 93
    ecall              # exit(3)
