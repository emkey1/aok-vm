#!/usr/bin/env python3
"""rel.py SOCKET DX DY [click] -- move a QEMU machine's relative mouse by DX, DY in small steps (so the guest's
acceleration stays out of it), and click if asked."""
import json, socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile('rw')
def cmd(name, **a):
    f.write(json.dumps({'execute': name, 'arguments': a}) + '\n'); f.flush()
    while True:
        r = json.loads(f.readline())
        if 'return' in r or 'error' in r: return r
f.readline(); cmd('qmp_capabilities')
dx, dy = int(sys.argv[2]), int(sys.argv[3])
def step(ax, n):
    sgn = 1 if n > 0 else -1
    for _ in range(abs(n) // 2):
        cmd('input-send-event', events=[{'type': 'rel', 'data': {'axis': ax, 'value': 2 * sgn}}]); time.sleep(0.02)
step('x', dx); step('y', dy)
if len(sys.argv) > 4:
    for d in (True, False):
        cmd('input-send-event', events=[{'type': 'btn', 'data': {'down': d, 'button': 'left'}}]); time.sleep(0.15)
