#!/usr/bin/env python3
"""qmp.py SOCKET CMD... -- drive a QEMU machine through QMP: a pointer with absolute positions (a tablet), keys,
and pictures. Positions are in the screen's own pixels (W x H below).
  move X Y | click X Y | dclick X Y | drag X1 Y1 X2 Y2 | key NAME[-NAME...] (QEMU key names, e.g. meta_l-q)
  keydown NAME | keyup NAME (to hold shift for a click) | type TEXT | shot FILE.ppm | sleep SECONDS | hmp 'COMMAND'
"""
import json, socket, sys, time
W, H = 640, 480
KEYS = {' ': 'spc', '.': 'dot', '-': 'minus', '/': 'slash', ',': 'comma', '\n': 'ret', ':': 'shift-semicolon',
        '_': 'shift-minus', '~': 'shift-grave_accent', '=': 'equal', ';': 'semicolon', '*': 'shift-8', '"': 'shift-apostrophe', "'": 'apostrophe'}
class Q:
    def __init__(self, path):
        if ':' in path and '/' not in path:      # HOST:PORT, a machine with -qmp tcp:...
            h, p = path.rsplit(':', 1); self.s = socket.create_connection((h, int(p)), timeout=20)
        else:
            self.s = socket.socket(socket.AF_UNIX); self.s.connect(path)
        self.f = self.s.makefile('rw')
        self.f.readline(); self.cmd('qmp_capabilities')
    def cmd(self, name, **args):
        self.f.write(json.dumps({'execute': name, 'arguments': args}) + '\n'); self.f.flush()
        while True:
            r = json.loads(self.f.readline())
            if 'return' in r or 'error' in r: return r
    def ev(self, *events): return self.cmd('input-send-event', events=list(events))
    def move(self, x, y):
        self.ev({'type': 'abs', 'data': {'axis': 'x', 'value': int(x * 32767 / (W - 1))}},
                {'type': 'abs', 'data': {'axis': 'y', 'value': int(y * 32767 / (H - 1))}}); time.sleep(0.15)
    def btn(self, down): self.ev({'type': 'btn', 'data': {'down': down, 'button': 'left'}}); time.sleep(0.12)
    def click(self, x, y): self.move(x, y); self.btn(True); self.btn(False)
    def key(self, combo):
        self.cmd('send-key', keys=[{'type': 'qcode', 'data': k} for k in combo.split('-')]); time.sleep(0.15)
q = Q(sys.argv[1]); a = sys.argv[2:]
while a:
    c = a.pop(0)
    if c == 'move': q.move(int(a.pop(0)), int(a.pop(0)))
    elif c == 'click': q.click(int(a.pop(0)), int(a.pop(0)))
    elif c == 'dclick': x, y = int(a.pop(0)), int(a.pop(0)); q.click(x, y); q.click(x, y)
    elif c == 'drag':
        x1, y1, x2, y2 = (int(a.pop(0)) for _ in range(4)); q.move(x1, y1); q.btn(True)
        for i in range(1, 11): q.move(x1 + (x2 - x1) * i // 10, y1 + (y2 - y1) * i // 10)
        q.btn(False)
    elif c == 'key': q.key(a.pop(0))
    elif c in ('keydown', 'keyup'):
        q.ev({'type': 'key', 'data': {'down': c == 'keydown', 'key': {'type': 'qcode', 'data': a.pop(0)}}}); time.sleep(0.15)
    elif c == 'type':
        for ch in a.pop(0): q.key(('shift-' + ch.lower()) if ch.isupper() else KEYS.get(ch, ch))
    elif c == 'shot': print(q.cmd('screendump', filename=a.pop(0)).get('error', 'ok'))
    elif c == 'sleep': time.sleep(float(a.pop(0)))
    elif c == 'hmp': print(q.cmd('human-monitor-command', **{'command-line': a.pop(0)}).get('return', ''))
    else: sys.exit('what is ' + c)
