#!/bin/zsh
# Helpers for driving the app under test. Source it: `source .agents/skills/ux-qa/scripts/session.sh`.
# Needs: macOS, Xcode command line tools, ffmpeg (for test clips), Accessibility + Screen Recording permission for the terminal.
# Everything works in screen POINTS: `uxqa_shot` writes images at point size, so a pixel in the PNG is a point on screen.
#
#   uxqa_setup                 compile the input, axdump and measure tools into $UXQA_DIR/bin (once per session)
#   uxqa_launch [url]          kill every running copy, start THIS worktree's build, optionally open a shot:// URL
#   uxqa_focus                 bring the app's front window to the front (works while someone is typing, unlike `activate`)
#   uxqa_shot NAME [X Y W H]   screenshot of the whole screen (toasts live at its bottom edge) or of a rect, to $UXQA_DIR/NAME.png
#   uxqa_click X Y | uxqa_dclick X Y | uxqa_drag X1 Y1 X2 Y2 [shift] | uxqa_scroll X Y DX DY
#   uxqa_key "text" | uxqa_keycode N ["command down, shift down"]
#   uxqa_window                prints the front window's x y w h; uxqa_resize W H sets its size
#   uxqa_ax [--json]           accessibility tree plus the problems it spots

UXQA_APP="${UXQA_APP:-Shot}"
UXQA_BUNDLE="${UXQA_BUNDLE:-$PWD/build/Shot.app}"
UXQA_DIR="${UXQA_DIR:-${TMPDIR:-/tmp}/uxqa}"
UXQA_SKILL="${UXQA_SKILL:-${${(%):-%x}:A:h}}"
export UXQA_APP
mkdir -p "$UXQA_DIR/bin"

uxqa_setup() {
  local tool
  for tool in input axdump measure; do
    swiftc -O "$UXQA_SKILL/$tool.swift" -o "$UXQA_DIR/bin/$tool" || return 1
  done
}

uxqa_launch() {
  pkill -x "$UXQA_APP"; sleep 1.5
  # A second copy (an installed release, say) would claim the shot:// URL scheme and the test would silently run the wrong build.
  pgrep -x "$UXQA_APP" >/dev/null && { echo "another $UXQA_APP is still running" >&2; return 1; }
  open -a "$UXQA_BUNDLE" || return 1
  sleep 3
  [[ -n "$1" ]] && { open -a "$UXQA_BUNDLE" "$1"; sleep 4 }
  uxqa_focus
  echo "running: $(ps -axo command | grep "[M]acOS/$UXQA_APP" | head -1)"
}

uxqa_focus() {
  osascript -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to set frontmost to true" \
            -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to perform action \"AXRaise\" of window 1" >/dev/null
  sleep 0.4
}

uxqa_shot() {
  local out="$UXQA_DIR/$1.png"
  if [[ -n "$2" ]]; then
    screencapture -x -R"$2,$3,$4,$5" "$out"
  else
    screencapture -x "$out"
  fi
  # Retina captures are twice the point size; scale down so image pixels equal points.
  local pw=$(( $(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}') ))
  local width=${4:-$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')}
  (( pw > width )) && sips --resampleWidth "$width" "$out" >/dev/null
  echo "$out"
}

uxqa_click()  { uxqa_focus; "$UXQA_DIR/bin/input" click "$@"; }
uxqa_dclick() { uxqa_focus; "$UXQA_DIR/bin/input" dclick "$@"; }
uxqa_drag()   { uxqa_focus; "$UXQA_DIR/bin/input" drag "$@"; }
uxqa_scroll() { uxqa_focus; "$UXQA_DIR/bin/input" scroll "$@"; }
uxqa_key()     { uxqa_focus; osascript -e "tell application \"System Events\" to keystroke \"$1\""; }
uxqa_keycode() {
  uxqa_focus
  if [[ -n "$2" ]]; then osascript -e "tell application \"System Events\" to key code $1 using {$2}"
  else osascript -e "tell application \"System Events\" to key code $1"; fi
}

uxqa_window() { osascript -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to get {position, size} of window 1"; }
# Setting the size from outside ignores the window's minSize, so use it to probe the layout, then confirm with a real drag.
uxqa_resize() { osascript -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to tell window 1 to set size to {$1, $2}"; sleep 1; }
uxqa_ax() { "$UXQA_DIR/bin/axdump" "$UXQA_APP" "$@"; }
uxqa_measure() { "$UXQA_DIR/bin/measure" "$@"; }

# Appearance matrix: uxqa_appearance dark|light
uxqa_appearance() {
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $([[ $1 == dark ]] && echo true || echo false)"
}
