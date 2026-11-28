#!/usr/bin/env python3
# i3variant.py NAME SRC -- one deliberate fault in a gadget of 2026-11-28, for a positive control. Seen by
# vectest (vec-gate.sh): lvx-order, stvx-order, lvx-align, mfocrf-shift, mtocrf-many, icbi-line, lswi-32.
# Also by vectest: addco-ov, ov-so, mullwo-ov, divwo-min, bcctr-sense, bcctrl-lr.
# Seen by ctxtest (ctx-test.sh): sync-stays, mtsrin-index, mfmsr-other, rfi-next.
import sys
name, src = sys.argv[1], sys.argv[2]
def one(path, old, new):
    p = src + '/' + path; s = open(p).read()
    assert s.count(old) == 1, (name, s.count(old), old)
    open(p, 'w').write(s.replace(old, new))
G, T = 'target/ppc/tcg/aok/gadgets.S', 'target/ppc/tcg/aok/translate.c'
if name == 'lvx-order':         # the halves not exchanged
    one(G, "    ldr x9, [_ip]\n    rev64 v0.16b, v0.16b\n    ext v0.16b, v0.16b, v0.16b, #8\n", "    ldr x9, [_ip]\n    rev64 v0.16b, v0.16b\n")
elif name == 'stvx-order':
    one(G, "    ldr q0, [x6]\n    rev64 v0.16b, v0.16b\n    ext v0.16b, v0.16b, v0.16b, #8\n", "    ldr q0, [x6]\n    rev64 v0.16b, v0.16b\n")
elif name == 'lvx-align':       # the address as it is
    one(G, ".gadget ppc_lvx\n    ea_x\n    and w7, w7, #0xfffffff0\n", ".gadget ppc_lvx\n    ea_x\n")
elif name == 'mfocrf-shift':    # the field at the bottom of rD
    one(G, "    ldr w10, [_cpu, x10]\n    lsl w10, w10, w11\n    str w10, [_cpu, x9]\n    gret 3\n", "    ldr w10, [_cpu, x10]\n    str w10, [_cpu, x9]\n    gret 3\n")
elif name == 'mtocrf-many':     # a mask of several bits obeyed
    one(T, "            if (crm && !(crm & (crm - 1))) {\n                emit2(c, G(mtcrf), gpr(d), crm);\n            }\n", "            emit2(c, G(mtcrf), gpr(d), crm);\n")
elif name == 'icbi-line':       # the address itself, not its line's
    one(T, "        cpu_ldl_mmu(env, ea & ~(env->dcache_line_size - 1),\n", "        cpu_ldl_mmu(env, ea,\n")
elif name == 'lswi-32':         # NB 0 as no bytes
    one(T, "    unsigned nb = (insn >> 11) & 31 ? (insn >> 11) & 31 : 32;\n", "    unsigned nb = (insn >> 11) & 31;\n")
elif name == 'sync-stays':      # the stream goes on after a switch of contexts
    one(G, ".gadget ppc_call_sync\n    call_c\n    cbnz x0, 1f\n", ".gadget ppc_call_sync\n    call_c\n")
elif name == 'mtsrin-index':    # the register number from the wrong field
    one(T, "                 : (env->gpr[(insn >> 11) & 31] >> 28) & 15;\n", "                 : (insn >> 16) & 15;\n")
elif name == 'mfmsr-other':     # another word of the state
    one(T, "        emit2(c, G(mov), gpr(d), offsetof(CPUPPCState, msr));\n", "        emit2(c, G(mov), gpr(d), offsetof(CPUPPCState, lr));\n")
elif name == 'rfi-next':        # on to the next insn
    one(T, "        return call_as(c, G(call_exit), aok_ppc_rfi, END);\n", "        return call_as(c, G(call_leave), aok_ppc_rfi, END);\n")
# the OE forms and bcctr on a CR bit (vectest)
elif name == 'addco-ov':        # addco leaves OV and SO alone
    one(G, ".gadget ppc_addco\n    rr\n    adds w10, w10, w11\n    ca_out\n    ov_out\n", ".gadget ppc_addco\n    rr\n    adds w10, w10, w11\n    ca_out\n")
elif name == 'ov-so':           # OV does not reach SO
    one(G, "    str \\reg, [_cpu, #AOK_PPC_ENV_OV]\n    orr w14, w14, \\reg\n", "    str \\reg, [_cpu, #AOK_PPC_ENV_OV]\n")
elif name == 'mullwo-ov':       # mullwo never overflows
    one(G, "    mov w10, w12\n    cset w13, ne\n", "    mov w10, w12\n    mov w13, #0\n")
elif name == 'divwo-min':       # 0x80000000 / -1 is no overflow
    one(G, "    ccmn w11, #1, #0, eq\n    cset w13, eq\n", "    ccmn w11, #1, #0, eq\n    mov w13, #0\n")
elif name == 'bcctr-sense':     # beqctr branches on the bit clear
    one(G, "    bclrc bcctr_t, 1, AOK_PPC_ENV_CTR\n", "    bclrc bcctr_t, 0, AOK_PPC_ENV_CTR\n")
elif name == 'bcctrl-lr':       # bcctrl leaves LR
    one(T, "        if (lk) {\n            emitg(c, G(set_lr));\n            aok_emit(&c->g, (uint32_t)(cia(c) + 4 - c->pc));\n        }\n        emitg(c, ctr ? ", "        emitg(c, ctr ? ")
else:
    sys.exit('no such variant')
