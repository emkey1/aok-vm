.global _start
_start:
    addi sp, sp, -64
    li t0, -2
    sd t0, 0(sp)          # store/load 64
    ld t1, 0(sp)
    bne t0, t1, fail
    li t0, 0x12345678
    sw t0, 8(sp)          # 32-bit store, signed + unsigned reload
    lw t1, 8(sp)
    lwu t2, 8(sp)
    bne t1, t2, fail      # positive value: identical
    li t0, -300
    sh t0, 16(sp)         # 16-bit truncation + sign/zero reload
    lh t1, 16(sp)
    li t3, -300
    bne t1, t3, fail
    lhu t2, 16(sp)
    li t3, 0xFED4         # 65236 = (-300) & 0xffff
    bne t2, t3, fail
    li t0, 200
    sb t0, 24(sp)         # byte: 200 as signed = -56
    lb t1, 24(sp)
    li t3, -56
    bne t1, t3, fail
    lbu t2, 24(sp)
    li t3, 200
    bne t2, t3, fail
    lla t4, buf           # store a string byte-by-byte, write() it back
    li t0, 'o'
    sb t0, 0(t4)
    sb t0, 1(t4)
    li t0, 'k'
    sb t0, 2(t4)
    li t0, '\n'
    sb t0, 3(t4)
    li a7, 64
    li a0, 1
    mv a1, t4
    li a2, 4
    ecall
    li a0, 0
    j done
fail:
    li a0, 1
done:
    li a7, 93
    ecall
.section .data
buf: .space 8
