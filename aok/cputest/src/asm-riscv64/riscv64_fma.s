.global _start
_start:
    li t0, 3
    fcvt.d.l f1, t0        # a = 3.0
    li t0, 4
    fcvt.d.l f2, t0        # b = 4.0
    li t0, 10
    fcvt.d.l f3, t0        # c = 10.0
    # fmadd: 3*4+10 = 22
    fmadd.d f4, f1, f2, f3
    fcvt.l.d t1, f4, rtz
    li a0, 1
    li t2, 22
    bne t1, t2, done
    # fmsub: 3*4-10 = 2
    fmsub.d f4, f1, f2, f3
    fcvt.l.d t1, f4, rtz
    li a0, 2
    li t2, 2
    bne t1, t2, done
    # fnmsub: -(3*4)+10 = -2
    fnmsub.d f4, f1, f2, f3
    fcvt.l.d t1, f4, rtz
    li a0, 3
    li t2, -2
    bne t1, t2, done
    # fnmadd: -(3*4)-10 = -22
    fnmadd.d f4, f1, f2, f3
    fcvt.l.d t1, f4, rtz
    li a0, 4
    li t2, -22
    bne t1, t2, done
    # single-precision fmadd: 2.5*2+1 = 6
    li t0, 5
    fcvt.s.l f1, t0
    li t0, 2
    fcvt.s.l f2, t0
    fdiv.s f1, f1, f2      # 2.5
    li t0, 1
    fcvt.s.l f3, t0
    fmadd.s f4, f1, f2, f3
    fcvt.l.s t1, f4, rtz
    li a0, 5
    li t2, 6
    bne t1, t2, done
    # the exact chronyd encoding: fmadd.d fa4, fa4, fa0, fa1 (0x5aa77743)
    fcvt.d.l fa4, t2       # 6.0
    li t0, 7
    fcvt.d.l fa0, t0       # 7.0
    li t0, 8
    fcvt.d.l fa1, t0       # 8.0
    .word 0x5aa77743       # fa4 = 6*7+8 = 50
    fcvt.l.d t1, fa4, rtz
    li a0, 6
    li t2, 50
    bne t1, t2, done
    # fclass.d: -inf, +0, qNaN
    li t0, 0
    fcvt.d.l f1, t0
    fclass.d t1, f1        # +0 -> bit 4
    li a0, 7
    li t2, 16
    bne t1, t2, done
    li t0, -1
    fcvt.d.l f1, t0
    fsqrt.d f1, f1         # NaN
    fclass.d t1, f1        # qNaN -> bit 9
    li a0, 8
    li t2, 512
    bne t1, t2, done
    li a0, 0
done:
    li a7, 93
    ecall
