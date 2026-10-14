#!/usr/bin/env python3
"""screen.py FILE.ppm [active] -- is ReactOS's "New Hardware Wizard" on this screen (a 1024x768 dump), and with
"active", does it have the keyboard? Exit 0 if so.

The wizard's left panel is one flat dark blue, about 160 by 310 pixels, centred on the screen; the desktop
behind it is a photograph, never flat. A black screen (booting) is flat too, hence the colour. The title bar
is near black (31) when the window is active and grey (72) when it is not: the wizard can come up behind
the shell, and keys sent then go to the shell.
"""
import sys


def ppm(path):
    data = open(path, "rb").read()
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            i = data.index(b"\n", i)
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    assert fields[0] == b"P6" and fields[3] == b"255", fields
    return int(fields[1]), int(fields[2]), data[i + 1:]


def pixel(w, px, x, y):
    o = (y * w + x) * 3
    return tuple(px[o:o + 3])


def wizard(path):
    w, h, px = ppm(path)
    if (w, h) != (1024, 768):
        return False
    first = pixel(w, px, 280, 330)
    r, g, b = first
    if not b > r + 30:
        return False
    return all(pixel(w, px, x, y) == first for y in range(330, 511, 6) for x in range(280, 336, 5))


def active(path):
    w, h, px = ppm(path)
    return wizard(path) and max(pixel(w, px, 600, 198)) < 50


if __name__ == "__main__":
    test = active if sys.argv[2:] == ["active"] else wizard
    sys.exit(0 if test(sys.argv[1]) else 1)
