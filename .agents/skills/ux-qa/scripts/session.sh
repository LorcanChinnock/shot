#!/bin/zsh
# Helpers for driving the app under test. Source it: `source .agents/skills/ux-qa/scripts/session.sh`.
# Needs: macOS, Xcode command line tools, ffmpeg (for test clips), Accessibility + Screen Recording permission for the terminal.
# Everything works in POINTS: `uxqa_shot` writes images at point size, so a pixel in the PNG is a point.
# Screenshots, URLs, `uxqa_ax`, `uxqa_window` and `uxqa_resize` leave the user's frontmost app alone. Only input takes focus.
#
#   uxqa_setup                 compile the input, axdump, measure and window tools into $UXQA_DIR/bin (once per session)
#   uxqa_launch [url]          kill every running copy, start THIS worktree's build in the background, optionally open a URL
#   uxqa_open URL              open a shot-dev:// URL in the background, without activating the app
#   uxqa_focus                 bring the app's front window to the front (works while someone is typing, unlike `activate`)
#   uxqa_shot NAME [-w ID]     screenshot of the app's front window (or window ID from `uxqa_windows`), even behind other
#                              windows, to $UXQA_DIR/NAME.png. Prints the window's screen origin: screen point = origin + pixel.
#   uxqa_screen NAME [X Y W H] screenshot of the whole screen or a screen rect: only what's visible, so it needs the screen
#   uxqa_windows               the app's on-screen windows, front to back: ID X Y W H layer title
#   uxqa_click X Y | uxqa_dclick X Y | uxqa_drag X1 Y1 X2 Y2 [shift] | uxqa_scroll X Y DX DY       (take focus)
#   uxqa_key "text" | uxqa_keycode N ["command down, shift down"]                                    (take focus)
#   uxqa_window                prints the front window's x y w h; uxqa_resize W H sets its size
#   uxqa_ax [--json]           accessibility tree plus the problems it spots
#   uxqa_contrast X Y W H [#bg] WCAG contrast of what's in a rect of the front window, captured at full resolution

UXQA_APP="${UXQA_APP:-ShotDev}"
UXQA_BUNDLE="${UXQA_BUNDLE:-$PWD/build/ShotDev.app}"
UXQA_DIR="${UXQA_DIR:-${TMPDIR:-/tmp}/uxqa}"
UXQA_SKILL="${UXQA_SKILL:-${${(%):-%x}:A:h}}"
export UXQA_APP
mkdir -p "$UXQA_DIR/bin"

uxqa_setup() {
  local tool
  for tool in input axdump measure window; do
    swiftc -O "$UXQA_SKILL/$tool.swift" -o "$UXQA_DIR/bin/$tool" || return 1
  done
}

uxqa_launch() {
  pkill -x "$UXQA_APP"; sleep 1.5
  # A second ShotDev (an installed make app build, say) would claim the shot-dev:// URL scheme and the test would silently
  # run the wrong build. An installed release answers shot:// only, so it can keep running.
  pgrep -x "$UXQA_APP" >/dev/null && { echo "another $UXQA_APP is still running" >&2; return 1; }
  open -g -a "$UXQA_BUNDLE" || return 1
  sleep 3
  [[ -n "$1" ]] && uxqa_open "$1"
  echo "running: $(ps -axo command | grep "[M]acOS/$UXQA_APP" | head -1)"
}

uxqa_focus() {
  osascript -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to set frontmost to true" \
            -e "tell application \"System Events\" to tell process \"$UXQA_APP\" to perform action \"AXRaise\" of window 1" >/dev/null
  sleep 0.4
}

# `-g` keeps the user's frontmost app in front. The app may still activate itself when a window opens.
uxqa_open() { open -g -a "$UXQA_BUNDLE" "$1"; sleep 4; }

uxqa_windows() { "$UXQA_DIR/bin/window" --all; }

# Captures one window by id, so it works while the window is behind others. -o leaves out the shadow, so the image is
# exactly the window's frame.
uxqa_shot() {
  local out="$UXQA_DIR/$1.png" frame
  if [[ "$2" == -w ]]; then frame=$(uxqa_windows | awk -v id="$3" '$1 == id {print $1, $2, $3, $4, $5}')
  else frame=$("$UXQA_DIR/bin/window"); fi
  [[ -n "$frame" ]] || { echo "no window to capture" >&2; return 1; }
  local id x y w h
  read id x y w h <<< "$frame"
  screencapture -x -o -l "$id" "$out" || return 1
  local pw=$(( $(sips -g pixelWidth "$out" | awk '/pixelWidth/{print $2}') ))
  (( pw > w )) && sips --resampleWidth "$w" "$out" >/dev/null
  echo "$out (origin $x $y)"
}

uxqa_screen() {
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
# Contrast of what's in a rect given in screen points, against the rect's top-left pixel or the colour given. Captures the front
# window at full resolution, because uxqa_shot scales Retina captures down and the blur lightens thin glyphs.
uxqa_contrast() {
  local id x y w h
  read id x y w h <<< "$("$UXQA_DIR/bin/window")"
  [[ -n "$id" ]] || return 1
  screencapture -x -o -l "$id" "$UXQA_DIR/contrast.png" || return 1
  local s=$(( $(sips -g pixelWidth "$UXQA_DIR/contrast.png" | awk '/pixelWidth/{print $2}') / w ))
  "$UXQA_DIR/bin/measure" "$UXQA_DIR/contrast.png" contrast $(( ($1 - x) * s )) $(( ($2 - y) * s )) $(( $3 * s )) $(( $4 * s )) $5
}

# Appearance matrix: uxqa_appearance dark|light
uxqa_appearance() {
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $([[ $1 == dark ]] && echo true || echo false)"
}
