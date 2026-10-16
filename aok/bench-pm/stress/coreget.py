#!/usr/bin/env python3
"""coreget.py LOG OUTDIR -- the cores a corecheck run sent out on the console (CORE-BEGIN name size,
gzip in base64, CORE-END), each written to OUTDIR under its name."""
import base64, gzip, os, re, sys

log, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
name, size, b64 = None, 0, []
for line in open(log, 'rb').read().decode('latin-1').replace('\r', '').split('\n'):
    if line.startswith('CORE-BEGIN '):
        _, path, size = line.split()
        name, size, b64 = os.path.basename(path), int(size), []
    elif line.startswith('CORE-END') and name:
        raw = gzip.decompress(base64.b64decode(''.join(b64)))
        p = os.path.join(out, name)
        open(p, 'wb').write(raw)
        print(f'{p}: {len(raw)} bytes{"" if len(raw) == size else f" (the guest said {size})"}')
        name = None
    elif name and re.fullmatch(r'[A-Za-z0-9+/=]+', line):
        b64.append(line)
