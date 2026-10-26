#!/usr/bin/env python3
"""index.py ZIPDIR [BASE_URL [INDEX_URL]] -- AOK VM's machine list (machines.json, beside this script) from the
zips build.sh and aok/reactos make: for each, the machine's name, a line about it, the zip's name, size and
SHA-256. The app carries those of BUNDLED (Resources/AOKMachines, the Xcode build's "Copy AOK VM machines")
and downloads the rest from BASE_URL + the zip's name; INDEX_URL is where it looks for a newer list.
"""
import hashlib
import json
import os
import sys

# id, the zip, the machine's name, the line about it, in the order the app lists them
ALPINE = "iSH-AOK's Alpine root on a machine of its own: busybox, apk, a terminal."
DEVUAN = "iSH-AOK's Devuan root on a machine of its own: sysvinit, apt, a terminal."
MACHINES = [
    ("alpine-aarch64", "alpine-3.24.2-aarch64.zip", "Alpine 3.24.2 (aarch64)", ALPINE),
    ("devuan-aarch64", "devuan-6-aarch64.zip", "Devuan 6 (aarch64)", DEVUAN),
    ("reactos", "reactos-0.4.16.zip", "ReactOS",
     "ReactOS 0.4.16, installed: a free system that runs Windows programs, on the x86 engine."),
    ("kolibrios", "kolibrios-0.7.7.0-8930.zip", "KolibriOS",
     "KolibriOS 0.7.7, a tiny and fast system written in assembly: a desktop, a web browser, an editor and "
     "games, from one floppy. Made by Mighty-Moth-Boy."),
    ("freedos", "freedos-1.4.zip", "FreeDOS 1.4",
     "FreeDOS 1.4, installed in full from its LiveCD: DOS with its programs, compilers and games, Freedoom "
     "among them. Made by Mighty-Moth-Boy."),
    ("alpine-x86_64", "alpine-3.24.2-x86_64.zip", "Alpine 3.24.2 (x86_64)", ALPINE),
    ("alpine-x86", "alpine-3.24.2-x86.zip", "Alpine 3.24.2 (x86)", ALPINE),
    ("alpine-riscv64", "alpine-3.24.2-riscv64.zip", "Alpine 3.24.2 (riscv64)", ALPINE),
    ("devuan-x86_64", "devuan-6-x86_64.zip", "Devuan 6 (x86_64)", DEVUAN),
    ("devuan-x86", "devuan-6-x86.zip", "Devuan 6 (x86)", DEVUAN),
    ("devuan-riscv64", "devuan-6-riscv64.zip", "Devuan 6 (riscv64)", DEVUAN),
]
ARCH = {"aarch64": "aarch64", "x86_64": "x86_64", "x86": "i386", "riscv64": "riscv64", "reactos": "i386",
        "kolibrios": "x86_64", "freedos": "x86_64"}
# The app carries these (the Xcode project's "Copy AOK VM machines" names them too).
BUNDLED = {"alpine-aarch64", "devuan-aarch64", "reactos"}
VERSION = 1


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    zips = sys.argv[1]
    base = sys.argv[2] if len(sys.argv) > 2 else \
        "https://github.com/emkey1/ish-AOK-rootfs/releases/download/aok-vm-machines-1/"
    index = sys.argv[3] if len(sys.argv) > 3 else \
        "https://raw.githubusercontent.com/emkey1/ish-AOK-rootfs/main/aok-vm/machines.json"
    machines = []
    for mid, zipname, name, summary in MACHINES:
        path = os.path.join(zips, zipname)
        machines.append({
            "id": mid, "name": name, "architecture": ARCH[mid.split("-")[-1]], "summary": summary,
            "file": zipname, "size": os.path.getsize(path), "sha256": sha256(path),
        })
    out = {"version": VERSION, "indexURL": index, "baseURL": base, "machines": machines}
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "machines.json")
    with open(dest, "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    for m in machines:
        print("%-26s %6.1f MB  %s%s" % (m["name"], m["size"] / 1e6, m["file"],
                                       "  (in the app)" if m["id"] in BUNDLED else ""))


if __name__ == "__main__":
    main()
