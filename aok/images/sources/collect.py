#!/usr/bin/env python3
"""collect.py [WHAT ...] -- the source of what AOK VM's machines hold, for the release that hosts their zips: GPLv2
asks that the corresponding source be offered from the same place as the binaries.

Reads the package databases of the root archives build.sh uses, fetches the source of exactly those versions, checks
it where the distribution gives a checksum, and packs one tar per asset in $OUT/assets (under the 2 GB a GitHub asset
may be). It runs nothing that it fetches. WHAT is any of linux alpine devuan reactos kolibrios freedos; default all.
    W=~/aok-vm-bench  OUT=$W/images-sources  ROOTFS=$W/images/rootfs
"""
import hashlib, json, lzma, os, re, shutil, subprocess, sys, tarfile, time, urllib.error, urllib.parse, urllib.request

W = os.environ.get("W", os.path.expanduser("~/aok-vm-bench"))
OUT = os.environ.get("OUT", W + "/images-sources")
ROOTFS = os.environ.get("ROOTFS", W + "/images/rootfs")
ARCHES = ("aarch64", "x86_64", "x86", "riscv64")
APORTS = "https://github.com/alpinelinux/aports"
DISTFILES = "https://distfiles.alpinelinux.org/distfiles/v3.24/"
KERNEL_APK_DIR = W + "/dl-kernel"
REACTOS_TAG = "0.4.16-release"
KOLIBRI_COMMIT = "d50642c"
FREEDOS = "https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.4/"
# Devuan's merged archive lists what it takes from Debian as it is; what Devuan changes is in its own.
DEVUAN = ("http://deb.devuan.org/merged/", "http://pkgmaster.devuan.org/devuan/")
SUITES = ("excalibur", "excalibur-updates", "excalibur-security", "excalibur-proposed-updates")
SNAPSHOT = "https://snapshot.debian.org"
log = []


def say(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def fetch(url, dest, sha256=None, sha512=None):
    """Fetch to dest, unless a file there already passes the check. Raises on a bad checksum or HTTP error."""
    def good():
        for name, want in (("sha256", sha256), ("sha512", sha512)):
            if want:
                h = hashlib.new(name)
                with open(dest, "rb") as f:
                    for b in iter(lambda: f.read(1 << 20), b""):
                        h.update(b)
                if h.hexdigest() != want:
                    return False
        return True
    if os.path.exists(dest) and good():
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "aok-vm-sources/1 (curl compatible)"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
                shutil.copyfileobj(r, f, 1 << 20)
            break
        except urllib.error.HTTPError:
            raise
        except Exception:
            if attempt == 2:
                raise
            time.sleep(5)
    os.replace(tmp, dest)
    if not good():
        os.remove(dest)
        raise ValueError(f"checksum mismatch: {url}")
    return dest


def pack(name, root, members=None):
    """root's contents (or the named members) as assets/name, uncompressed: the parts are compressed already."""
    os.makedirs(OUT + "/assets", exist_ok=True)
    path = f"{OUT}/assets/{name}"
    with tarfile.open(path + ".part", "w") as t:
        for m in members or sorted(os.listdir(root)):
            t.add(os.path.join(root, m), arcname=m)
    os.replace(path + ".part", path)
    size = os.path.getsize(path)
    assert size < 2_000_000_000, f"{name} is {size} bytes"
    say(f"packed {name}: {size / 1e6:.0f} MB")
    return path


def aports():
    d = OUT + "/work/aports"
    if not os.path.isdir(d):
        subprocess.check_call(["git", "clone", "-q", "--filter=blob:none", "--no-checkout", APORTS, d])
    return d


def aports_dir(commit, origin, dest):
    """main/ORIGIN (or community/ORIGIN) at commit, under dest; returns its path."""
    d = aports()
    for repo in ("main", "community"):
        path = f"{repo}/{origin}"
        if subprocess.run(["git", "-C", d, "cat-file", "-e", f"{commit}:{path}/APKBUILD"], capture_output=True).returncode == 0:
            os.makedirs(dest, exist_ok=True)
            a = subprocess.Popen(["git", "-C", d, "archive", commit, path], stdout=subprocess.PIPE)
            subprocess.check_call(["tar", "-x", "-C", dest, "-f", "-"], stdin=a.stdout)
            a.wait()
            return f"{dest}/{path}"
    raise KeyError(f"{origin} at {commit}")


def apkbuild_sources(path):
    """The fetched files of an APKBUILD, as (name, url, sha512), read as text: it is never run."""
    text = open(path + "/APKBUILD", errors="replace").read()
    var = {}
    for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=("([^"]*)"|\'([^\']*)\'|(\S*))', text, re.M):
        var.setdefault(m[1], m[3] if m[3] is not None else m[4] if m[4] is not None else m[5])
    def expand(s):
        def one(m):
            n = m[1] or m[3]
            v = var.get(n, "")
            op = m[2]
            if op:
                o = re.match(r'(%%|%|##|#|//|/|:)(.*)', op)
                if o:
                    kind, arg = o[1], o[2]
                    pat = re.escape(arg).replace(r'\*', '.*').replace(r'\?', '.')
                    if kind == "%":
                        for i in range(len(v), -1, -1):
                            if re.fullmatch(pat, v[i:]):
                                return v[:i]
                    elif kind == "%%":
                        for i in range(0, len(v) + 1):
                            if re.fullmatch(pat, v[i:]):
                                return v[:i]
                    elif kind == "#":
                        for i in range(0, len(v) + 1):
                            if re.fullmatch(pat, v[:i]):
                                return v[i:]
                    elif kind == "##":
                        for i in range(len(v), -1, -1):
                            if re.fullmatch(pat, v[:i]):
                                return v[i:]
                    elif kind in ("/", "//"):
                        a, _, b = arg.partition("/")
                        return v.replace(a, b) if kind == "//" else v.replace(a, b, 1)
            return v
        return re.sub(r'\$\{([A-Za-z_][A-Za-z0-9_]*)([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)()', lambda m: one(_M(m)), s)
    class _M:
        def __init__(self, m):
            self.g = (None, m[1], m[2] or "", m[3])
        def __getitem__(self, i):
            return self.g[i]
    for _ in range(3):
        for k in list(var):
            var[k] = expand(var[k])
    m = re.search(r'^source="([^"]*)"', text, re.M)
    sha = {}
    s = re.search(r'^sha512sums="([^"]*)"', text, re.M)
    if s:
        for line in s[1].split("\n"):
            f = line.split()
            if len(f) == 2:
                sha[f[1]] = f[0]
    out = []
    for entry in expand(m[1]).split() if m else []:
        name, url = entry.split("::", 1) if "::" in entry else (entry.rsplit("/", 1)[-1], entry)
        if re.match(r'https?://|ftp://', url):
            out.append((name, url, sha.get(name)))
    return out, var


def fetch_apk_sources(dir_, tree):
    got = []
    files, var = apkbuild_sources(tree)
    for name, url, sha in files:
        dest = f"{tree}/{name}"
        for u in (DISTFILES + urllib.parse.quote(name), url):
            try:
                fetch(u, dest, sha512=sha)
                got.append(name)
                break
            except Exception as e:
                last = e
        else:
            raise RuntimeError(f"{tree}: {name}: {last}")
    return got, var


def alpine_db():
    pk = {}
    for a in ARCHES:
        t = subprocess.run(["tar", "-xOf", f"{ROOTFS}/alpine-minirootfs-3.24.2-{a}.tar.xz", "lib/apk/db/installed"],
                           capture_output=True, text=True).stdout
        for rec in t.split("\n\n"):
            d = {l[0]: l[2:] for l in rec.split("\n") if len(l) > 2 and l[1] == ":"}
            if "P" in d:
                pk[(d.get("o", d["P"]), d["V"], d.get("c"))] = d.get("L", "")
    return pk


def disk_db(arch="aarch64"):
    """The apk database of the machine's own disk, which also has what job.sh added (openrc), by scanning the raw
    image for its records: nothing mounted or run."""
    raw = f"{OUT}/work/alpine-{arch}.raw"
    if not os.path.exists(raw):
        os.makedirs(os.path.dirname(raw), exist_ok=True)
        subprocess.check_call(["qemu-img", "convert", "-O", "raw", f"{W}/images/stage/alpine-{arch}/disk.qcow2", raw])
    pk = {}
    with open(raw, "rb") as f:
        pos, chunk = 0, 1 << 24
        while True:
            f.seek(pos)
            b = f.read(chunk)
            if not b:
                break
            for m in re.finditer(rb'C:Q1[A-Za-z0-9+/=]{20,}\nP:([^\n]+)\nV:([^\n]+)\n(?:[A-Za-z]:[^\n]*\n){0,24}', b):
                d = {l[0:1].decode(): l[2:].decode("latin1") for l in m[0].split(b"\n") if len(l) > 2 and l[1:2] == b":"}
                if d.get("c") and d.get("o"):
                    pk[(d["o"], d["V"], d["c"])] = d.get("L", "")
            pos += chunk - 4096
    return pk


def do_alpine():
    root = OUT + "/work/alpine"
    shutil.rmtree(root, ignore_errors=True)
    pk = dict(alpine_db())
    pk.update(disk_db())
    say(f"alpine: {len(pk)} source packages:", sorted(k[0] + "-" + k[1] for k in pk))
    index = []
    for (origin, ver, commit), lic in sorted(pk.items()):
        if origin == "linux-lts":
            continue
        tree = aports_dir(commit, origin, f"{root}/{origin}-{ver}")
        got, _ = fetch_apk_sources(root, tree)
        index.append(dict(origin=origin, version=ver, aports_commit=commit, license=lic, fetched=got))
        say("  ", origin, ver, got)
    json.dump(index, open(root + "/INDEX.json", "w"), indent=1)
    return pack("sources-alpine-3.24.2.tar", root)


def do_linux():
    root = OUT + "/work/linux"
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root)
    infos = set()
    for apk in sorted(os.listdir(KERNEL_APK_DIR)):
        if apk.endswith(".apk"):
            t = subprocess.run(["tar", "-xOf", f"{KERNEL_APK_DIR}/{apk}", ".PKGINFO"], capture_output=True, text=True).stdout
            d = dict(l.split(" = ", 1) for l in t.split("\n") if " = " in l)
            infos.add((d["origin"], d["pkgver"], d["commit"]))
    assert len(infos) == 1, infos
    origin, ver, commit = infos.pop()
    say("linux:", origin, ver, commit)
    tree = aports_dir(commit, origin, root)
    full = ver.split("-")[0]
    major = ".".join(full.split(".")[:2])
    fetch(f"https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-{major}.tar.xz", f"{root}/linux-{major}.tar.xz")
    fetch(f"https://cdn.kernel.org/pub/linux/kernel/v6.x/patch-{full}.xz", f"{root}/patch-{full}.xz")
    json.dump(dict(origin=origin, version=ver, aports_commit=commit), open(root + "/INDEX.json", "w"), indent=1)
    return pack(f"sources-linux-{ver}-alpine.tar", root)


def debian_index():
    idx = {}
    for base in DEVUAN:
        for suite in SUITES:
            try:
                with urllib.request.urlopen(f"{base}dists/{suite}/main/source/Sources.xz", timeout=120) as r:
                    t = lzma.decompress(r.read()).decode("utf-8", "replace")
            except Exception as e:
                say("  no index for", base, suite, e)
                continue
            for rec in t.split("\n\n"):
                pkg = re.search(r'^Package: (\S+)', rec, re.M)
                ver = re.search(r'^Version: (\S+)', rec, re.M)
                dr = re.search(r'^Directory: (\S+)', rec, re.M)
                sh = re.search(r'^Checksums-Sha256:\n((?: .*\n?)+)', rec, re.M)
                if pkg and ver and dr and sh:
                    idx.setdefault((pkg[1], ver[1]), (base + dr[1], [l.split() for l in sh[1].strip().split("\n")]))
    return idx


def snapshot_files(pkg, ver):
    url = f"{SNAPSHOT}/mr/package/{urllib.parse.quote(pkg)}/{urllib.parse.quote(ver)}/srcfiles?fileinfo=1"
    with urllib.request.urlopen(url, timeout=120) as r:
        d = json.load(r)
    out = []
    for f in d["result"]:
        info = d["fileinfo"][f["hash"]][0]
        out.append((info["name"], f"{SNAPSHOT}/file/{f['hash']}"))
    return out


def do_devuan():
    root = OUT + "/work/devuan"
    os.makedirs(root, exist_ok=True)
    want = {}
    for a in ARCHES:
        f = f"{ROOTFS}/devuan-minirootfs-6.0-{a}.tar.xz"
        t = subprocess.run(["tar", "-xOf", f, "./var/lib/dpkg/status"], capture_output=True, text=True).stdout or \
            subprocess.run(["tar", "-xOf", f, "var/lib/dpkg/status"], capture_output=True, text=True).stdout
        for rec in t.split("\n\n"):
            d = {}
            for l in rec.split("\n"):
                m = re.match(r"(Package|Version|Source|Status): (.*)", l)
                if m:
                    d[m[1]] = m[2]
            if "Package" not in d or "installed" not in d.get("Status", ""):
                continue
            s, v = d.get("Source", d["Package"]), d["Version"]
            m = re.match(r"(\S+) \((.*)\)", s)
            if m:
                s, v = m[1], m[2]
            v = re.sub(r"\+b\d+$", "", v)
            want.setdefault((s, v), set()).add(a)
    say(f"devuan: {len(want)} source packages")
    idx = debian_index()
    say(f"  the index has {len(idx)}")
    index, missing = [], []
    for (s, v), arches in sorted(want.items()):
        d = f"{root}/{s}_{v}"
        names = []
        try:
            if (s, v) in idx:
                dr, files = idx[(s, v)]
                for sha, _, name in files:
                    fetch(f"{dr}/{urllib.parse.quote(name)}", f"{d}/{name}", sha256=sha)
                    names.append(name)
                where = urllib.parse.urlparse(dr).netloc
            else:
                for name, url in snapshot_files(s, v):
                    fetch(url, f"{d}/{name}")
                    names.append(name)
                where = "snapshot.debian.org"
            index.append(dict(source=s, version=v, arches=sorted(arches), files=names, source_of_files=where))
            say("  ", s, v, where, len(names))
        except Exception as e:
            missing.append([s, v, str(e)])
            say("   MISSING", s, v, e)
    json.dump(dict(packages=index, missing=missing), open(root + "/INDEX.json", "w"), indent=1)
    if missing:
        say("devuan: MISSING", missing)
    return pack("sources-devuan-6.tar", root)


def do_reactos():
    root = OUT + "/work/reactos"
    os.makedirs(root, exist_ok=True)
    fetch(f"https://github.com/reactos/reactos/archive/refs/tags/{REACTOS_TAG}.tar.gz", f"{root}/reactos-{REACTOS_TAG}.tar.gz")
    return pack("sources-reactos-0.4.16.tar", root)


def do_kolibrios():
    root = OUT + "/work/kolibrios"
    os.makedirs(root, exist_ok=True)
    d = OUT + "/work/kolibrios.git"
    if not os.path.isdir(d):
        for u in ("https://git.kolibrios.org/KolibriOS/kolibrios.git", "https://github.com/KolibriOS/kolibrios.git"):
            if subprocess.run(["git", "clone", "-q", "--bare", u, d]).returncode == 0:
                say("kolibrios from", u)
                break
            shutil.rmtree(d, ignore_errors=True)
    full = subprocess.check_output(["git", "-C", d, "rev-parse", KOLIBRI_COMMIT], text=True).strip()
    out = f"{root}/kolibrios-{full[:10]}.tar.xz"
    if not os.path.exists(out):
        a = subprocess.Popen(["git", "-C", d, "archive", f"--prefix=kolibrios-{full[:10]}/", full], stdout=subprocess.PIPE)
        with open(out, "wb") as f:
            subprocess.check_call(["xz", "-6", "-T0"], stdin=a.stdout, stdout=f)
        a.wait()
    say("kolibrios", full)
    return pack("sources-kolibrios-0.7.7.0-8930.tar", root)


def do_freedos():
    root = OUT + "/work/freedos"
    os.makedirs(root, exist_ok=True)
    # The official CD the machine is installed from, which is its own source: each package has a SOURCE folder.
    fetch(FREEDOS + "FD14-LiveCD.zip", f"{root}/FD14-LiveCD.zip")
    return pack("sources-freedos-1.4.tar", root, ["FD14-LiveCD.zip"])


def main():
    what = sys.argv[1:] or ["linux", "alpine", "devuan", "reactos", "kolibrios", "freedos"]
    for w in what:
        say("==", w)
        try:
            globals()["do_" + w]()
        except Exception as e:
            say("FAILED", w, repr(e))
    say("COLLECT-DONE")


if __name__ == "__main__":
    main()
