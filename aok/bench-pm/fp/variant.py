#!/usr/bin/env python3
# variant.py NAME gadgets.S -- a deliberate fault in one single-precision gadget, for a positive control:
#   adds-exact   fadds and fsubs call every sum exact (FI and XX never set by them)
#   fmas-b       fmadds and the rest add the product to A instead of B
#   muls-exact   fmuls calls every product exact
#   divs-swap    fdivs divides B by A
# (A first idea, fmuls in double and rounded to single afterwards, is no fault: two singles' product is exact in
# double, so there is no second rounding. It changed nothing, which is how that was noticed.)
import sys
name, path = sys.argv[1], sys.argv[2]
s = open(path).read()
def one(old, new):
    global s
    assert s.count(old) == 1, (name, old)
    s = s.replace(old, new)
if name == 'adds-exact':
    one("    fadd s6, s6, s7\n    fcmp s6, #0.0\n    cset w11, ne\n    fcvt d0, s20\n", "    fadd s6, s6, s7\n    fcmp s6, #0.0\n    mov w11, #0\n    fcvt d0, s20\n")
elif name == 'fmas-b':
    one("    fmadd s20, s21, s22, s23\n", "    fmadd s20, s21, s22, s21\n")
elif name == 'muls-exact':
    one("    fnmsub s4, s21, s22, s20\n    fcmp s4, #0.0\n    cset w11, ne\n", "    fnmsub s4, s21, s22, s20\n    fcmp s4, #0.0\n    mov w11, #0\n")
elif name == 'divs-swap':
    one("    fdiv s20, s21, s22\n", "    fdiv s20, s22, s21\n")
# The special cases (2026-11-27): a fault in each path that finishes an op the arithmetic alone does not.
elif name == 'nan-order':       # a quiet NaN taken from frC before frB
    one("    mov x10, x2\n    cmp x5, x13\n    b.hi 4f\n    mov x10, x3\n", "    mov x10, x3\n    cmp x6, x13\n    b.hi 4f\n    mov x10, x2\n")
elif name == 'nan-mask':        # a single op keeps a NaN's low 29 bits
    one("    and x10, x10, #0xffffffffe0000000\n", "")
elif name == 'snan-b':          # a signalling frB passes as quiet
    one("    tbz x5, #52, 9f\n", "")
elif name == 'infzero':         # infinity * 0 + a quiet NaN is not invalid
    one("    ccmp x6, #0, #0, eq\n    b.eq 9f\n", "    ccmp x6, #0, #0, eq\n")
elif name == 'inf-any':         # any infinite result is taken for exact (an overflow, a zero divide)
    one("    ccmp x6, x13, #4, ne\n    b.ne 9f\n    mov w16, #0x05", "    ccmp x6, x13, #4, ne\n    mov w16, #0x05")
elif name == 'inf-class':       # - infinity classed as + infinity
    one("    mov w17, #0x09\n", "    mov w17, #0x05\n")
elif name == 'zero-any':        # a product that underflowed to zero is taken for exact
    one("    fcmp \\c, #0.0\n    b.ne \\slow\n0:  mov w11, #0\n", "    fcmp \\c, #0.0\n0:  mov w11, #0\n")
elif name == 'quot-any':        # a quotient that underflowed to zero is taken for exact
    one("    b.eq \\done\n    b \\slow\n", "    b \\done\n")
elif name == 'fma-zero':        # A or C zero: the sum called inexact
    one("    mov w11, #0                 /* a zero of a zero operand */\n", "    mov w11, #1\n")
elif name == 'fma-tiny':        # a tiny product under B': called exact
    one("    exp_in d3, 110, 2046, 7f    /* tiny, under a B' it cannot move */\n    mov w11, #1\n", "    exp_in d3, 110, 2046, 7f\n    mov w11, #0\n")
elif name == 'fma-cancel':      # a cancelled sum: the zero's sign wrong
    one("    cmp x13, #2045\n    b.hi 9f\n", "    fneg d0, d0\n")
elif name == 'fmas-zero':
    one("    b.hs 0f\n    mov w11, #0\n    fcmp d1, #0.0\n    b.eq 2b\n    fcmp d2, #0.0\n    b.eq 2b\n    exp_in d3, 948", "    b.hs 0f\n    mov w11, #1\n    fcmp d1, #0.0\n    b.eq 2b\n    fcmp d2, #0.0\n    b.eq 2b\n    exp_in d3, 948")
elif name == 'fmas-tiny':
    one("    exp_in d3, 948, 1150, 7f\n    mov w11, #1\n", "    exp_in d3, 948, 1150, 7f\n    mov w11, #0\n")
elif name == 'fmas-cancel':
    one("    cmp x13, #1149\n    b.hi 9f\n", "    fneg d0, d0\n")
else:
    sys.exit('no such variant')
open(path, 'w').write(s)
