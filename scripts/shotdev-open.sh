#!/bin/zsh
# Sends a shot-dev:// link to the ShotDev that's running, such as the one Xcode's Run started.
#
#   scripts/shotdev-open.sh 'shot-dev://pick-color'
#
# A plain `open 'shot-dev://…'` lets LaunchServices pick any ShotDev it has seen, such as a stale build in another
# checkout's DerivedData, and starts it if it isn't running. This sends the link to the running copy by its path, and
# stops when none or more than one is running, so a test never reaches the wrong build.
set -euo pipefail

if [[ $# -ne 1 || $1 != shot-dev://* ]]; then
    echo "Usage: $0 'shot-dev://<action>'" >&2
    exit 64
fi

running=("${(@f)$(pgrep -lf '/ShotDev.app/Contents/MacOS/ShotDev' | grep -v ' -frontend ' || true)}")
running=(${running:#})
case ${#running} in
0)
    echo "No ShotDev is running. Run it from Xcode first (the Shot scheme, ⌘R)." >&2
    exit 1
    ;;
1) ;;
*)
    echo "${#running} ShotDev copies are running, so the link could reach the wrong one. Stop all but one:" >&2
    printf '  %s\n' "${running[@]}" >&2
    exit 1
    ;;
esac

executable=${running[1]#* }
executable=${executable%% -*}
app=${executable%/Contents/MacOS/ShotDev}
open -a "$app" "$1"
echo "Sent $1 to $app"
