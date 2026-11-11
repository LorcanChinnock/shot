#!/bin/bash
# Measures the app's fast and idle paths on this Mac and checks them against the budgets in docs/performance.md.
# Drives an installed Shot through its URL scheme (shot-dev:// for ShotDev), so it quits any running copy first and needs:
#   - Screen Recording permission for Shot (the captures),
#   - Accessibility permission for this terminal (keys for the gallery, closing Shot's windows with ⌘W).
# It takes 20 full-screen screenshots and moves them out of the capture folder afterwards, into a folder it prints.
# For the gallery it points the app's save folder at a seeded library of 1,500 images for a minute, then puts it back.
# Usage: scripts/perf.sh [path/to/Shot.app]   (default build/ShotDev.app, the Release build make bundle archives)
set -euo pipefail

# Quits every other ShotDev, including one Xcode is running, and the installed Shot, which clean_up reopens.
"$(dirname "$0")/dev.sh" prepare
app="${1:-$(dirname "$0")/../build/ShotDev.app}"
[ -d "$app" ] || { echo "No app at $app; run make bundle first" >&2; exit 1; }
# Absolute and resolved, as ps reports the running executable.
app=$(cd "$app" && pwd -P)
cd "$(dirname "$0")/.."
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")
scheme=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$app/Contents/Info.plist")

# Budgets, about 1.5x the baselines in docs/performance.md. Empty means not measured: printed, not checked.
budget_launch_ms="150"
budget_capture_ms="285"
budget_memory_mb="30"
budget_idle_cpu="1.0"
budget_gallery_selection_ms="30"
budget_gallery_filter_ms="36"
budget_quick_access_ms="14"
budget_menu_ms="62"
budget_settings_ms="113"
budget_gallery_open_ms="160"
budget_editor_ms="324"
budget_video_editor_ms="99"

work=$(mktemp -d "${TMPDIR:-/tmp}/shot-perf.XXXXXX")
started=$(date "+%Y-%m-%d %H:%M:%S")

signposts() { # name → ndjson lines of that signpost from this app since the script started
  /usr/bin/log show --signpost --start "$started" --style ndjson \
    --predicate "subsystem == \"$bundle_id\" AND category == \"perf\" AND signpostName == \"$1\"" 2>/dev/null
}

# name [end message] → milliseconds of each completed interval of that signpost, one per line.
durations() {
  signposts "$1" | python3 -c '
import json, sys
from datetime import datetime
message = sys.argv[1]
begins = {}
for line in sys.stdin:
    entry = json.loads(line)
    if "signpostType" not in entry:
        continue
    when = datetime.strptime(entry["timestamp"], "%Y-%m-%d %H:%M:%S.%f%z")
    if entry["signpostType"] == "begin":
        begins[entry["signpostID"]] = when
    elif entry["signpostType"] == "end" and entry["signpostID"] in begins and entry.get("eventMessage", "").startswith(message):
        print((when - begins.pop(entry["signpostID"])).total_seconds() * 1000)' "${2:-}"
}

median() { python3 -c 'import sys,statistics; v=[float(x) for x in sys.stdin.read().split()]; print(round(statistics.median(v)) if v else "")'; }

quit_shot() {
  pkill -x "$executable" || true
  while pgrep -x "$executable" >/dev/null; do sleep 0.1; done
}

pid() { pgrep -x "$executable" | head -1; }

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
[ "$(ps -o comm= -p "$running")" = "$app/Contents/MacOS/$executable" ] || { echo "The running Shot isn't $app" >&2; exit 1; }

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
# The gallery step points the save folder at its own library; put the user's back however the script ends.
save_folder_before=$(defaults read "$bundle_id" saveFolder 2>/dev/null || true)
gallery_library=""
# shellcheck disable=SC2329 # Called by the EXIT trap and after the gallery step.
restore_save_folder() {
  [ -n "$gallery_library" ] || return 0
  if [ -n "$save_folder_before" ]; then
    defaults write "$bundle_id" saveFolder "$save_folder_before"
  else
    defaults delete "$bundle_id" saveFolder 2>/dev/null || true
  fi
  gallery_library=""
}
# shellcheck disable=SC2329 # Called by the EXIT trap.
clean_up() {
  restore_save_folder
  move_captures
  scripts/dev.sh stop || true
}
trap clean_up EXIT
for i in $(seq 20); do
  open -g -a "$app" "$scheme://capture-fullscreen"
  sleep 1.5
  # Stop after the first capture if it wasn't copied, usually a missing Screen Recording permission, rather than fail 20 times.
  if [ "$i" = 1 ] && ! signposts "Capture to clipboard" | grep -q '"eventMessage":"copied"'; then
    echo "The first capture wasn't copied. Check Shot's Screen Recording permission and that Copy to clipboard is on in Settings › Capture." >&2
    exit 1
  fi
done
sleep 2
capture_ms=$(durations "Capture to clipboard" copied | median)
# Quick Access: from each capture's card being added to the frame that first shows it.
quick_access_ms=$(durations "Quick Access open" card | median)

# Memory after use: the footprint once the 20 captures' Quick Access cards have gone.
sleep 10
memory_mb=$(footprint -p "$(pid)" 2>/dev/null | python3 -c '
import re, sys
match = re.search(r"Footprint: ([\d.]+) (B|KB|MB|GB)", sys.stdin.read())
scale = {"B": 1 / 2**20, "KB": 1 / 1024, "MB": 1, "GB": 1024}
print(round(float(match.group(1)) * scale[match.group(2)]) if match else "")')

# Gallery selection and filter: a library of 1,500 screenshots over 300 days, driven with arrow keys and search typing.
gallery_library="$work/library"
python3 -c '
import os, struct, sys, zlib
from datetime import datetime, timedelta
folder = sys.argv[1]
os.makedirs(folder)
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
width, height = 480, 300
rows = b"".join(b"\0" + bytes(v for x in range(width) for v in (x * 255 // width, y * 255 // height, 160)) for y in range(height))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=300)
for i in range(1500):
    when = start + timedelta(days=i // 5, hours=9 + i % 5, minutes=i % 60)
    path = os.path.join(folder, when.strftime("Shot %Y-%m-%d at %H.%M.%S.png"))
    with open(path, "wb") as file:
        file.write(png)
    os.utime(path, (when.timestamp(), when.timestamp()))
' "$gallery_library"
defaults write "$bundle_id" saveFolder "$gallery_library"
open -g -a "$app" "$scheme://gallery"
sleep 4
# Arrow keys go through the same path as a click. Down moves past the visible rows, so the grid scrolls too.
osascript -e "tell application \"System Events\" to tell process \"$executable\"
  set frontmost to true
  delay 0.5
  repeat 30 times
    key code 124
    delay 0.15
  end repeat
  repeat 15 times
    key code 125
    delay 0.15
  end repeat
  keystroke \"f\" using command down
  delay 0.5
  repeat with letter in characters of \"Shot 2026\"
    keystroke letter
    delay 0.3
  end repeat
  repeat 9 times
    key code 51
    delay 0.3
  end repeat
  keystroke \"w\" using command down
end tell" >/dev/null
sleep 2
restore_save_folder
gallery_selection_ms=$(durations "Gallery selection" "items=1500" | median)
gallery_filter_ms=$(durations "Gallery filter" | median)

shot=$(find "$folder" -maxdepth 1 -newer "$marker" -name "*.png" | head -1)
clip="$work/clip.mp4"
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" -c:v libx264 -pix_fmt yuv420p "$clip"
else
  cp docs/media/recording.mp4 "$clip"
fi
encode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
[ -n "$shot" ] || { echo "No capture found in $folder to open in the editor" >&2; exit 1; }
close_windows() {
  osascript -e "tell application \"System Events\" to tell process \"$executable\"
    set frontmost to true
    repeat (count of windows) times
      keystroke \"w\" using command down
      delay 0.5
    end repeat
  end tell" >/dev/null
}

# Menu: click Shot's menu bar icon five times with real mouse events, closing the menu with Escape each time. A click on
# the icon never reaches the app, so each one is timed from the moment this script posts it to the app's "Menu shown" event.
icon=$(osascript -e "tell application \"System Events\" to tell process \"$executable\" to get {position, size} of menu bar item 1 of menu bar 2" | tr -d ' ')
clicks="$work/menu-clicks"
python3 -c '
import ctypes, sys, time
cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class Point(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]
cg.CGEventCreateMouseEvent.restype = ctypes.c_void_p
cg.CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, Point, ctypes.c_uint32]
cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
x, y, width, height = (float(v) for v in sys.argv[1].split(","))
centre = Point(x + width / 2, y + height / 2)
for _ in range(5):
    print(time.time(), flush=True)
    for kind in (1, 2):  # left mouse down, up
        cg.CGEventPost(0, cg.CGEventCreateMouseEvent(None, kind, centre, 0))
    time.sleep(1.5)
    for down in (True, False):  # Escape
        cg.CGEventPost(0, cg.CGEventCreateKeyboardEvent(None, 53, down))
    time.sleep(1)
' "$icon" > "$clicks"
menu_ms=$(signposts "Menu shown" | python3 -c '
import json, sys
from datetime import datetime
clicks = [float(line) for line in open(sys.argv[1])]
shown = sorted(datetime.strptime(json.loads(line)["timestamp"], "%Y-%m-%d %H:%M:%S.%f%z").timestamp() for line in sys.stdin if "signpostType" in line)
for click in clicks:
    after = [when for when in shown if click <= when < click + 1]
    if after:
        print((after[0] - click) * 1000)' "$clicks" | median)

# Window opening: Settings, the gallery, the editor and the video editor, three times each, closing them in between.
for link in "$scheme://settings?section=general" "$scheme://gallery" "$scheme://annotate?path=$(encode "$shot")" "$scheme://edit-video?path=$(encode "$clip")"; do
  for _ in 1 2 3; do
    open -g -a "$app" "$link"
    sleep 3
    close_windows
    sleep 1
  done
done
settings_ms=$(durations "Window open" settings | median)
gallery_open_ms=$(durations "Window open" gallery | median)
editor_ms=$(durations "Window open" editor | median)
video_editor_ms=$(durations "Window open" "video editor" | median)

# Idle CPU: open and close the editor, video editor and gallery, then the CPU time used over the next 30 s.
open -g -a "$app" "$scheme://annotate?path=$(encode "$shot")"
open -g -a "$app" "$scheme://edit-video?path=$(encode "$clip")"
open -g -a "$app" "$scheme://gallery"
sleep 4
close_windows
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
row "Gallery selection" "$gallery_selection_ms" ms "$budget_gallery_selection_ms"
row "Gallery filter" "$gallery_filter_ms" ms "$budget_gallery_filter_ms"
row "Quick Access open" "$quick_access_ms" ms "$budget_quick_access_ms"
row "Menu open" "$menu_ms" ms "$budget_menu_ms"
row "Settings open" "$settings_ms" ms "$budget_settings_ms"
row "Gallery open" "$gallery_open_ms" ms "$budget_gallery_open_ms"
row "Editor open" "$editor_ms" ms "$budget_editor_ms"
row "Video editor open" "$video_editor_ms" ms "$budget_video_editor_ms"
echo
exit $failed
