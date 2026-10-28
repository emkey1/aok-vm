# ros-desk.py REF DIR: for each screenshot in DIR (named by seconds), its difference from REF (the desktop), on a
# 32x24 thumbnail made by sips; prints seconds and difference, sorted.
import os, subprocess, sys, struct, tempfile
def thumb(p):
    t = tempfile.mktemp(suffix=".bmp")
    subprocess.run(["sips", "-z", "24", "32", "-s", "format", "bmp", p, "--out", t], capture_output=True)
    d = open(t, "rb").read(); os.unlink(t)
    off, = struct.unpack_from("<I", d, 10); w, h = struct.unpack_from("<ii", d, 18); bpp, = struct.unpack_from("<H", d, 28)
    step = bpp // 8; row = (w * step + 3) & ~3
    return [d[off + y * row + x * step: off + y * row + x * step + 3] for y in range(abs(h)) for x in range(w)]
ref = thumb(sys.argv[1])
for f in sorted(os.listdir(sys.argv[2])):
    if not f.endswith(".png") or f.startswith("tmp"): continue
    px = thumb(os.path.join(sys.argv[2], f))
    diff = sum(abs(a - b) for p, q in zip(px, ref) for a, b in zip(p, q)) / (len(ref) * 3)
    print(f"{float(f[:-4]):7.2f} {diff:6.1f}")
