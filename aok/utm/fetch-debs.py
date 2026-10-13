#!/usr/bin/env python3
"""fetch-debs.py URIS OUTDIR -- fetch what `apt-get install --print-uris` listed, many connections at once.

Each line of URIS is: 'URL' NAME SIZE HASH. Files are split into ranges fetched in parallel, because a
mirror that gives one connection 85 kB/s gives twelve of them a megabyte. apt in the guest checks the
hashes; here only the sizes are checked.
"""
import concurrent.futures
import os
import sys
import urllib.request

CHUNK = 4 << 20


def fetch(url, start, end, path):
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if len(data) == end - start + 1:
                with open(path, "wb") as f:
                    f.write(data)
                return
        except Exception as e:       # a slow or dropped connection: try again
            last = e
    raise SystemExit(f"could not fetch {url} {start}-{end}: {last}")


def main():
    uris, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    jobs, files = [], []
    for line in open(uris):
        url, name, size = line.split()[:3]
        url, size = url.strip("'"), int(size)
        if os.path.exists(f"{out}/{name}") and os.path.getsize(f"{out}/{name}") == size:
            continue
        parts = []
        for i, start in enumerate(range(0, size, CHUNK)):
            part = f"{out}/.{name}.{i}"
            parts.append(part)
            jobs.append((url, start, min(start + CHUNK, size) - 1, part))
        files.append((name, size, parts))
    with concurrent.futures.ThreadPoolExecutor(max_workers=14) as pool:
        for f in [pool.submit(fetch, *j) for j in jobs]:
            f.result()
    for name, size, parts in files:
        with open(f"{out}/{name}", "wb") as f:
            for p in parts:
                f.write(open(p, "rb").read())
                os.remove(p)
        assert os.path.getsize(f"{out}/{name}") == size, name
    print(f"{len(files)} files fetched, {sum(s for _, s, _ in files) >> 20} MB")


if __name__ == "__main__":
    main()
