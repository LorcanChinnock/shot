#!/bin/bash
# Measures the app's fast and idle paths on this Mac and checks them against the budgets in docs/performance.md.
# Drives an installed Shot through the shot:// scheme, so it quits any running copy first and needs:
#   - Screen Recording permission for Shot (the captures),
#   - Accessibility permission for this terminal (closing Shot's windows with ⌘W).
# It takes 20 full-screen screenshots and moves them out of the capture folder afterwards, into a folder it prints.
# Usage: scripts/perf.sh [path/to/Shot.app]   (default /Applications/Shot.app)
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-/Applications/Shot.app}"
[ -d "$app" ] || { echo "No app at $app; run make app first" >&2; exit 1; }
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")

# Budgets, about 1.5x the baselines in docs/performance.md. Empty means not measured yet: printed, not checked.
budget_launch_ms=""
budget_capture_ms=""
budget_memory_mb=""
budget_idle_cpu="1.0"

work=$(mktemp -d "${TMPDIR:-/tmp}/shot-perf.XXXXXX")
started=$(date "+%Y-%m-%d %H:%M:%S")

signposts() { # name → ndjson lines of that signpost from this app since the script started
  /usr/bin/log show --signpost --start "$started" --style ndjson \
    --predicate "subsystem == \"$bundle_id\" AND category == \"perf\" AND signpostName == \"$1\"" 2>/dev/null
}

median() { python3 -c 'import sys,statistics; v=[float(x) for x in sys.stdin.read().split()]; print(round(statistics.median(v)) if v else "")'; }

quit_shot() {
  pkill -x Shot || true
  while pgrep -x Shot >/dev/null; do sleep 0.1; done
}

pid() { pgrep -x Shot | head -1; }

# Launch → ready: process start to hotkeys registered, from the app's "Ready" event, three launches.
ready_count() { signposts Ready | grep -c '"signpostType":"event"' || true; }
for _ in 1 2 3; do
  quit_shot
  before=$(ready_count)
  open -a "$app"
  for _ in $(seq 50); do
    [ "$(ready_count)" -gt "$before" ] && break
    sleep 0.4
  done
  sleep 2
done
launch_ms=$(signposts Ready | python3 -c '
import json, re, sys
for line in sys.stdin:
    entry = json.loads(line)
    match = re.search(r"launch ms=(\d+)", entry.get("eventMessage", ""))
    if entry.get("signpostType") == "event" and match:
        print(match.group(1))' | median)
running=$(pid)
[ "$(ps -o comm= -p "$running")" = "$app/Contents/MacOS/Shot" ] || { echo "The running Shot isn't $app" >&2; exit 1; }

# Capture → clipboard: 20 full-screen captures, timed by the app's "Capture to clipboard" interval.
folder=$(defaults read "$bundle_id" saveFolder 2>/dev/null || echo "$HOME/Pictures/Shot")
marker="$work/marker"
touch "$marker"
for _ in $(seq 20); do
  open -g "shot://capture-fullscreen"
  sleep 1.5
done
sleep 2
capture_ms=$(signposts "Capture to clipboard" | python3 -c '
import json, sys
from datetime import datetime
begins = {}
for line in sys.stdin:
    entry = json.loads(line)
    if "signpostType" not in entry:
        continue
    when = datetime.strptime(entry["timestamp"], "%Y-%m-%d %H:%M:%S.%f%z")
    if entry["signpostType"] == "begin":
        begins[entry["signpostID"]] = when
    elif entry["signpostType"] == "end" and entry.get("eventMessage") == "copied" and entry["signpostID"] in begins:
        print((when - begins.pop(entry["signpostID"])).total_seconds() * 1000)' | median)

# Memory after use: the footprint once the 20 captures' Quick Access cards have gone.
sleep 10
memory_mb=$(footprint -p "$(pid)" 2>/dev/null | python3 -c '
import re, sys
match = re.search(r"Footprint: ([\d.]+) (B|KB|MB|GB)", sys.stdin.read())
scale = {"B": 1 / 2**20, "KB": 1 / 1024, "MB": 1, "GB": 1024}
print(round(float(match.group(1)) * scale[match.group(2)]) if match else "")')

# Idle CPU: open and close the editor, video editor and gallery, then average %CPU over 30 s.
shot=$(find "$folder" -maxdepth 1 -newer "$marker" -name "*.png" | head -1)
clip="$work/clip.mp4"
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" -c:v libx264 -pix_fmt yuv420p "$clip"
fi
[ -n "$shot" ] && open -g "shot://annotate?path=$shot"
[ -f "$clip" ] && open -g "shot://edit-video?path=$clip"
open -g "shot://gallery"
sleep 4
osascript -e 'tell application "System Events" to tell process "Shot"
  set frontmost to true
  repeat (count of windows) times
    keystroke "w" using command down
    delay 0.5
  end repeat
end tell' >/dev/null
sleep 5
idle_cpu=$(for _ in $(seq 30); do ps -o %cpu= -p "$(pid)"; sleep 1; done | python3 -c 'import sys,statistics; print(round(statistics.mean(float(x) for x in sys.stdin.read().split()), 2))')

# Move this run's captures out of the user's folder.
moved="$work/captures"
mkdir -p "$moved"
find "$folder" -maxdepth 1 -newer "$marker" -type f -exec mv {} "$moved/" \;

failed=0
row() { # name value unit budget
  local verdict="not budgeted"
  if [ -z "$2" ]; then
    verdict="NOT MEASURED"
    failed=1
  elif [ -n "$4" ]; then
    if python3 -c "import sys; sys.exit(0 if float('$2') <= float('$4') else 1)"; then verdict="ok (budget $4)"; else verdict="OVER (budget $4)"; failed=1; fi
  fi
  printf "%-22s %10s %-4s %s\n" "$1" "$2" "$3" "$verdict"
}
echo
row "Launch → ready" "$launch_ms" ms "$budget_launch_ms"
row "Capture → clipboard" "$capture_ms" ms "$budget_capture_ms"
row "Memory after use" "$memory_mb" MB "$budget_memory_mb"
row "Idle CPU" "$idle_cpu" % "$budget_idle_cpu"
echo
echo "This run's captures were moved to $moved"
exit $failed
