#!/bin/bash
# triage.sh [SINCE] -- what AOK VM's users have reported, for a release (README.md, "Releasing", step 1): the open
# issues and pull requests on emkey1/aok-vm and the issues closed but updated since SINCE, then the crash reports and
# TestFlight feedback that Xcode's Organizer has downloaded. "*" marks what is new or updated since SINCE, an ISO
# date; by default the newest GitHub release's. The Organizer's copies are the user's to download, in Xcode: Window >
# Organizer, AOK VM, Crashes, then Feedback. When they are older than SINCE this says so: then they are not "none".
set -e
REPO=emkey1/aok-vm
PRODUCT=$HOME/Library/Developer/Xcode/Products/app.ish.aok.vm
SINCE=${1:-$(gh release view -R $REPO --json createdAt -q .createdAt)}
echo "== reports since $SINCE (* = new or updated since)"
gh issue list -R $REPO --state open --limit 200 --json number,title,updatedAt,author \
    --jq '.[] | "\(if .updatedAt > "'"$SINCE"'" then "*" else " " end) issue #\(.number) (\(.author.login), \(.updatedAt[0:10])): \(.title)"'
gh issue list -R $REPO --state closed --limit 200 --search "updated:>=${SINCE:0:10}" --json number,title,updatedAt \
    --jq '.[] | "* closed issue #\(.number), updated \(.updatedAt[0:10]): \(.title)"'
gh pr list -R $REPO --state open --limit 200 --json number,title,updatedAt,author \
    --jq '.[] | "\(if .updatedAt > "'"$SINCE"'" then "*" else " " end) PR #\(.number) (\(.author.login), \(.updatedAt[0:10])): \(.title)"'
python3 -I - "$PRODUCT" "$SINCE" <<'EOF'
import datetime, glob, json, os, re, sys
product, since = sys.argv[1], datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00"))

def fresh(path, what):
    if not os.path.exists(path):
        print(f"! no {what} downloaded at all: Xcode, Window > Organizer, AOK VM, {what}")
        return
    when = datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc)
    if when < since:
        print(f"! {what} last downloaded {when:%Y-%m-%d}, before {since:%Y-%m-%d}: download them again "
              f"(Xcode, Window > Organizer, AOK VM, {what})")

# Crashes: one .xccrashpoint per signature, its logs in the legacy text format.
fresh(f"{product}/Crashes/ListablePoints.json", "Crashes")
for point in sorted(glob.glob(f"{product}/Crashes/Points/*.xccrashpoint")):
    logs = glob.glob(f"{point}/Filters/*/Logs/*.crash")
    if not logs:
        continue
    builds, newest, newest_log = set(), None, None
    for log in logs:
        text = open(log, errors="replace").read()
        m = re.search(r"^Version:\s+\S+ \((\d+)\)", text, re.M)
        builds.add(m.group(1) if m else "?")
        m = re.search(r"^Date/Time:\s+(\S+ \S+ [-+]\d{4})", text, re.M)
        if m:
            t = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f %z")
            if newest is None or t > newest:
                newest, newest_log = t, text
    text = newest_log or open(logs[0], errors="replace").read()
    # Xcode's symbolicated copy, when it has made one, names the engine's frames too
    symbolicated = glob.glob(f"{point}/Filters/*/Logs/LocallySymbolicated/*.crash")
    if symbolicated:
        text = open(max(symbolicated), errors="replace").read()
    exc = re.search(r"^Exception Type:\s+(.*)$", text, re.M)
    frames = re.search(r"^Thread \d+ Crashed.*\n((?:\d+ .*\n)+)", text, re.M)
    frames = frames.group(1).splitlines() if frames else []
    # the first frame of the app's own, or of an engine, else the top one
    top = next((f for f in frames if re.match(r"\d+\s+(AOK VM|qemu-)", f)), frames[0] if frames else "")
    top = re.sub(r"\s+0x[0-9a-f]+\s+", " ", top.split(None, 1)[1]) if top else "?"
    mark = "*" if newest and newest > since else " "
    print(f"{mark} crash {os.path.basename(point)}: {len(logs)} logs, builds {', '.join(sorted(builds))}, "
          f"newest {newest:%Y-%m-%d}: {exc.group(1).strip() if exc else '?'} at {top}")
    print(f"      {point}")

# TestFlight feedback: one .xcfeedbackpoint per report, a screenshot (maybe with a comment) or a comment alone.
fresh(f"{product}/Feedback/ListableFeedback.json", "Feedback")
items = []
for info in glob.glob(f"{product}/Feedback/Points/*/Filters/*/PointInfo.json"):
    d = json.load(open(info))
    t = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
    items.append((t, d, os.path.dirname(info)))
for t, d, where in sorted(items, key=lambda i: i[0]):
    dev = d.get("deviceMetadata", {})
    comment = " ".join(d.get("comment", "(no comment)").split())
    print(f"{'*' if t > since else ' '} feedback {t:%Y-%m-%d}, build {d['appInfo']['buildNumber']}, "
          f"{dev.get('deviceModel', '?')} iOS {dev.get('osVersion', '?')}, {d['kind']}"
          f"{', %d images' % d['imageCount'] if d.get('imageCount') else ''}: {comment[:300]}")
EOF
