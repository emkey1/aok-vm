#!/usr/bin/env python3
# avvariant.py NAME SRC -- one deliberate fault in an AltiVec gadget or its translation, for a positive control:
# avstress (av-gate.sh) must print a line that is not TCG's for each.
import sys
name, src = sys.argv[1], sys.argv[2]
def one(path, old, new):
    p = src + '/' + path; s = open(p).read()
    assert s.count(old) == 1, (name, s.count(old), old)
    open(p, 'w').write(s.replace(old, new))
G, T = 'target/ppc/tcg/aok/gadgets.S', 'target/ppc/tcg/aok/translate.c'
V = {
# floating point: where the host's result is not QEMU's
'fp-result-tiny': (G, "    fp_ok 5, 2, 6\n    and v3.16b, v3.16b, v4.16b\n    and v3.16b, v3.16b, v5.16b\n    fp_all 3\n    vput 4, 2\n",
                      "    and v3.16b, v3.16b, v4.16b\n    fp_all 3\n    vput 4, 2\n"),                # a result under the least normal kept
'fp-denormal-in': (G, "    facgt v\\m\\().4s, v\\v\\().4s, v30.4s\n", "    fcmeq v\\m\\().4s, v\\v\\().4s, v\\v\\().4s\n"),  # only NaNs go to C
'fp-nan-in':      (G, "    fcmeq v\\t\\().4s, v\\v\\().4s, #0.0\n    orr v\\m\\().16b, v\\m\\().16b, v\\t\\().16b\n",
                      "    fcmeq v\\t\\().4s, v\\v\\().4s, #0.0\n    orr v\\m\\().16b, v\\m\\().16b, v\\t\\().16b\n    fcmeq v\\t\\().4s, v\\v\\().4s, v\\v\\().4s\n    orn v\\m\\().16b, v\\m\\().16b, v\\t\\().16b\n"),  # NaNs stay
'fma-result':     (G, "    fp_ok 4, 7, 6\n    and v3.16b, v3.16b, v5.16b\n    and v3.16b, v3.16b, v4.16b\n", "    and v3.16b, v3.16b, v5.16b\n"),
'nmsub-sign':     (G, "    .if \\neg\n    fneg v7.4s, v1.4s\n    .else\n    mov v7.16b, v1.16b\n    .endif\n    fmla v7.4s, v0.4s, v2.4s\n    .if \\neg\n    fneg v7.4s, v7.4s\n    .endif\n",
                      "    mov v7.16b, v1.16b\n    .if \\neg\n    fmls v7.4s, v0.4s, v2.4s\n    .else\n    fmla v7.4s, v0.4s, v2.4s\n    .endif\n"),  # vB - vA*vC: a zero's sign
'fma-operands':   (G, "    fmla v7.4s, v0.4s, v2.4s\n", "    fmla v7.4s, v0.4s, v1.4s\n"),
'vsubfp-swap':    (G, "    v_fp2 vsubfp, fsub\n", "    v_fp2 vsubfp, fadd\n"),
'vcmpgefp-gt':    (G, "    v_fcmp vcmpgefp, fcmge\n", "    v_fcmp vcmpgefp, fcmgt\n"),
'vrfim-z':        (G, ".macro op_vrfim\n    frintm v2.4s, v0.4s\n", ".macro op_vrfim\n    frintz v2.4s, v0.4s\n"),
'vrefp-result':   (G, "    v_fp1 vrefp, 1\n", "    v_fp1 vrefp, 0\n"),
'vctsxs-low':     (G, "    fcmgt v5.4s, v3.4s, v1.4s\n    orr v4.16b, v4.16b, v5.16b\n", "    fcmgt v5.4s, v3.4s, v1.4s\n"),       # saturating downward not recorded
'vctuxs-neg':     (G, "    fmov v5.4s, #-1.0\n    fcvtzu v0.4s, v1.4s\n", "    movi v5.4s, #0\n    fcvtzu v0.4s, v1.4s\n"),            # -0.5 taken for saturating
'vcfsx-scale':    (T, "              (uint64_t)(127 - a) << 23);\n", "              (uint64_t)(127 + a) << 23);\n"),
# places
'vperm-index':    (G, "    movi v3.16b, #31\n    bic v2.16b, v3.16b, v2.16b\n", "    movi v3.16b, #31\n    and v2.16b, v3.16b, v2.16b\n"),
'vsldoi-swap':    (G, "    ldr q17, [_cpu, x10]\n    ldr q16, [_cpu, x11]\n    ldr q2, [x13]\n", "    ldr q16, [_cpu, x10]\n    ldr q17, [_cpu, x11]\n    ldr q2, [x13]\n"),
'vmrg-swap':      (G, "    \\insn v0.\\arr, v1.\\arr, v0.\\arr\n    vput 3\n    .endm\n", "    \\insn v0.\\arr, v0.\\arr, v1.\\arr\n    vput 3\n    .endm\n"),
'vsplt-offset':   (T, "        int at = (((a << vece) & 15) ^ 15) & ~((1 << vece) - 1);\n", "        int at = ((a << vece) & 15) & ~((1 << vece) - 1);\n"),
'vsel-swap':      (G, "    bsl v2.16b, v1.16b, v0.16b\n", "    bsl v2.16b, v0.16b, v1.16b\n"),
'vslo-dir':       (G, "    v_octets vslo, sub\n", "    v_octets vslo, add\n"),
'vsl-carry':      (G, "    lsl x12, x12, x11\n    orr x13, x13, x15\n", "    lsl x12, x12, x11\n"),
'lvsr-16':        (G, "    mov w11, #16\n    sub w10, w11, w10\n", "    neg w10, w10\n"),
'vmule-low':      (G, "    v_mule vmuleub, ushr, 8h, 8\n", "    v_mulo vmuleub, ushr, 8h, 8\n"),
'vupk-half':      (G, ".gadget ppc_vupkhsh\n    vr1\n    sshll2 v0.4s, v0.8h, #0\n", ".gadget ppc_vupkhsh\n    vr1\n    sshll v0.4s, v0.4h, #0\n"),
# saturation and its record
'sat-unrecorded': (G, "    eor v2.16b, v2.16b, v0.16b\n    vsat 2, 3\n    vput 4\n", "    eor v2.16b, v2.16b, v0.16b\n    vput 4\n"),
'pk-unrecorded':  (G, "    mvn v3.16b, v3.16b\n    vsat 3, 3\n    vput 4, 2\n", "    mvn v3.16b, v3.16b\n    vput 4, 2\n"),
'vsumsws-sat':    (G, "    orr w15, w15, w14\n", "    orr w15, w15, wzr\n"),
'vsum2sws-sign':  (G, "    shl v3.2d, v1.2d, #32\n    sshr v3.2d, v3.2d, #32\n", "    shl v3.2d, v1.2d, #32\n    ushr v3.2d, v3.2d, #32\n"),
'mhradd-round':   (G, "    v_mhadd vmhraddshs, 1\n", "    v_mhadd vmhraddshs, 0\n"),
'vmsummbm-sign':  (G, "    sshll v3.8h, v0.8b, #0\n    ushll v5.8h, v1.8b, #0\n", "    sshll v3.8h, v0.8b, #0\n    sshll v5.8h, v1.8b, #0\n"),
'mfvscr-sat':     (G, "    cset w12, ne\n    orr w10, w10, w12\n    add x9, _cpu, x9\n    stp x10, xzr, [x9]\n", "    cset w12, ne\n    add x9, _cpu, x9\n    stp x10, xzr, [x9]\n"),
# the rest
'cr6-swap':       (G, "    lsl w11, w11, #1\n    orr w10, w11, w10, lsl #3\n", "    lsl w10, w10, #1\n    orr w10, w10, w11, lsl #3\n"),
'vavg-trunc':     (G, "    v_rr vavgub, urhadd, 16b\n", "    v_rr vavgub, uhadd, 16b\n"),
'vsra-logical':   (G, "    neg v1.\\arr, v1.\\arr\n    sshl v0.\\arr, v0.\\arr, v1.\\arr\n", "    neg v1.\\arr, v1.\\arr\n    ushl v0.\\arr, v0.\\arr, v1.\\arr\n"),
'vrl-half':       (G, "    ushl v0.\\arr, v0.\\arr, v2.\\arr\n    orr v0.16b, v0.16b, v3.16b\n", "    mov v0.16b, v3.16b\n"),
'vsubcuw-borrow': (G, "    cmhs v0.4s, v0.4s, v1.4s\n    ushr v0.4s, v0.4s, #31\n", "    cmhi v0.4s, v0.4s, v1.4s\n    ushr v0.4s, v0.4s, #31\n"),
'lvewx-align':    (T, "        case 71: helper_LVEWX(env, d, ea & ~3); return;\n", "        case 71: helper_LVEWX(env, d, ea); return;\n"),
'vspltis-sign':   (T, "        int32_t simm = (int32_t)(a << 27) >> 27;\n", "        int32_t simm = a;\n"),
'mtvscr-word':    (T, "    case 1604: helper_mtvscr(env, b->VsrW(3)); return;\n", "    case 1604: helper_mtvscr(env, b->VsrW(0)); return;\n"),
}
if name == 'list':
    print(' '.join(V)); sys.exit(0)
one(*V[name])
