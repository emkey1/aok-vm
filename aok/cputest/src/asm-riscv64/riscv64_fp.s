.global _start
_start:
    li t0, 3
    fcvt.d.w f0, t0        # 3.0
    li t1, 4
    fcvt.d.w f1, t1        # 4.0
    fadd.d f2, f0, f1      # 7.0
    fcvt.w.d a0, f2, rtz   # 7
    li a7, 93
    ecall
