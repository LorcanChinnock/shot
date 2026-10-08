#!/bin/bash
# Measures the app's fast and idle paths on this Mac and checks them against the budgets in docs/performance.md.
# Drives an installed Shot through the shot:// scheme, so it quits any running copy first and needs:
#   - Screen Recording permission for Shot (the captures),
#   - Accessibility permission for this terminal (closing Shot's windows with ⌘W).
# It takes 20 full-screen screenshots and moves them out of the capture folder afterwards, into a folder it prints.
# Usage: scripts/perf.sh [path/to/Shot.app]   (default /Applications/Shot.app)
set -euo pipefail

app="${1:-/Applications/Shot.app}"
[ -d "$app" ] || { echo "No app at $app; run make app first" >&2; exit 1; }
# Absolute and resolved, as ps reports the running executable.
app=$(cd "$app" && pwd -P)
cd "$(dirname "$0")/.."
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")

# Budgets, about 1.5x the baselines in docs/performance.md. Empty means not measured: printed, not checked.
budget_launch_ms="150"
budget_capture_ms="285"
budget_memory_mb="865"
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
  ready=0
  for _ in $(seq 50); do
    if [ "$(ready_count)" -gt "$before" ]; then
      ready=1
      break
    fi
    sleep 0.4
  done
  [ "$ready" = 1 ] || { echo "Shot didn't report Ready within 20 s of launching" >&2; exit 1; }
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
# Shot writes to the save folder, or to a temporary one when saving is off (Preferences.captureFolder).
if [ "$(defaults read "$bundle_id" saveAfterCapture 2>/dev/null || echo 1)" = 0 ]; then
  folder="${TMPDIR:-/tmp}/Shot"
else
  folder=$(defaults read "$bundle_id" saveFolder 2>/dev/null || echo "$HOME/Pictures/Shot")
fi
marker="$work/marker"
touch "$marker"
moved="$work/captures"
# Move this run's captures out of the capture folder however the script ends, since they show the screen.
# shellcheck disable=SC2329 # Called by the EXIT trap.
move_captures() {
  mkdir -p "$moved"
  if [ -d "$folder" ]; then
    find "$folder" -maxdepth 1 -newer "$marker" -type f -exec mv {} "$moved/" \;
  fi
  echo "This run's captures were moved to $moved"
}
trap move_captures EXIT
for i in $(seq 20); do
  open -g -a "$app" "shot://capture-fullscreen"
  sleep 1.5
  # Stop after the first capture if it wasn't copied, usually a missing Screen Recording permission, rather than fail 20 times.
  if [ "$i" = 1 ] && ! signposts "Capture to clipboard" | grep -q '"eventMessage":"copied"'; then
    echo "The first capture wasn't copied. Check Shot's Screen Recording permission and that Copy after capture is on." >&2
    exit 1
  fi
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

# Idle CPU: open and close the editor, video editor and gallery, then the CPU time used over the next 30 s.
shot=$(find "$folder" -maxdepth 1 -newer "$marker" -name "*.png" | head -1)
clip="$work/clip.mp4"
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" -c:v libx264 -pix_fmt yuv420p "$clip"
fi
encode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
[ -n "$shot" ] || { echo "No capture found in $folder to open in the editor" >&2; exit 1; }
open -g -a "$app" "shot://annotate?path=$(encode "$shot")"
if [ -f "$clip" ]; then
  open -g -a "$app" "shot://edit-video?path=$(encode "$clip")"
fi
open -g -a "$app" "shot://gallery"
sleep 4
osascript -e 'tell application "System Events" to tell process "Shot"
  set frontmost to true
  repeat (count of windows) times
    keystroke "w" using command down
    delay 0.5
  end repeat
end tell' >/dev/null
sleep 5
# ps %cpu is a decaying average over about a minute, so it would still count the windows just closed; CPU time isn't.
cpu_seconds() { ps -o time= -p "$(pid)" | python3 -c '
import sys
days, _, clock = sys.stdin.read().strip().rpartition("-")
parts = [float(p) for p in clock.split(":")]
print(float(days or 0) * 86400 + sum(value * 60 ** index for index, value in enumerate(reversed(parts))))'; }
cpu_before=$(cpu_seconds)
sleep 30
cpu_after=$(cpu_seconds)
idle_cpu=$(python3 -c "print(round(($cpu_after - $cpu_before) / 30 * 100, 2))")

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
exit $failed
