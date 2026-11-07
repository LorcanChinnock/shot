#!/bin/sh
# Keeps exactly one ShotDev running, whichever way it starts. Xcode's Run (⌘R, or Claude's RunProject) calls
# `prepare` from the Shot scheme's pre-action, and `make run` calls `run`, so both quit every other copy first: one
# from another worktree, one Xcode is debugging, or an old install in /Applications. The installed release registers the
# same global shortcuts, so a hotkey could reach it instead; `prepare` quits it and `stop` reopens it, but only if it was
# running.
#
# Usage: scripts/dev.sh prepare            quit every ShotDev and the release, before a launch
#        scripts/dev.sh run [app arguments] build Debug as Xcode's Run does, then launch it, e.g. -AppleLanguages '(de)'
#        scripts/dev.sh stop               quit ShotDev and reopen the release if prepare quit it
#        scripts/dev.sh status             show which copies of ShotDev and Shot are running
set -eu
cd "$(dirname "$0")/.."

release=/Applications/Shot.app
legacy=/Applications/ShotDev.app
debug_app=build/DerivedData/Build/Products/Debug/ShotDev.app
# Outside the repository, so a run in one worktree and a stop in another share it. /tmp empties at restart, when the
# release opens at login anyway.
state="/tmp/shot-dev-$(id -u)"
marker="$state/release-was-running"

# Waits up to $2 tenths of a second for every process named $1 to exit.
gone() {
    i=0
    while pgrep -x "$1" >/dev/null; do
        [ "$i" -ge "$2" ] && return 1
        i=$((i + 1))
        sleep 0.1
    done
}

# Quits every process named $1, then kills what's left after 3 seconds. A copy Xcode is debugging would stop in lldb on
# a signal, and even SIGKILL can't end it while it's paused there, so its debugserver goes first, which ends it with it.
quit() {
    pgrep -x "$1" >/dev/null || return 0
    debugged=0
    for pid in $(pgrep -x "$1"); do
        parent=$(ps -o ppid= -p "$pid" | tr -d ' ')
        case "$(ps -o comm= -p "$parent" 2>/dev/null)" in
            */debugserver) kill "$parent" 2>/dev/null && debugged=1 ;;
        esac
    done
    [ "$debugged" = 1 ] && gone "$1" 20 && return 0
    pkill -x "$1" || true
    gone "$1" 30 && return 0
    pkill -9 -x "$1" || true
    gone "$1" 50 && return 0
    echo "error: $1 is still running; quit it in Activity Monitor." >&2
    exit 1
}

prepare() {
    if pgrep -x Shot >/dev/null; then
        mkdir -p "$state"
        touch "$marker"
        quit Shot
        echo "Quit the installed Shot; scripts/dev.sh stop reopens it."
    fi
    if pgrep -x ShotDev >/dev/null; then
        quit ShotDev
        echo "Quit the ShotDev that was already running."
    fi
    # make run used to install here. A second copy is one more for Spotlight, Launchpad or Open at login to start.
    if [ -d "$legacy" ]; then
        rm -rf "$legacy"
        echo "Removed $legacy, left by an older make run."
    fi
}

stop() {
    quit ShotDev
    if [ -f "$marker" ]; then
        rm -f "$marker"
        if [ -d "$release" ]; then
            open "$release"
            echo "Stopped ShotDev and reopened Shot."
            return
        fi
    fi
    echo "Stopped ShotDev."
}

status() {
    found=0
    for name in ShotDev Shot; do
        for pid in $(pgrep -x "$name"); do
            found=1
            echo "$name (pid $pid): $(ps -o comm= -p "$pid")"
        done
    done
    [ "$found" = 1 ] || echo "Neither ShotDev nor Shot is running."
    [ -f "$marker" ] && echo "The installed Shot was quit for ShotDev; scripts/dev.sh stop reopens it."
    return 0
}

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
    prepare) prepare ;;
    run)
        scripts/xcodebuild.sh -scheme Shot -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -quiet build
        prepare
        # open, not the executable, so macOS treats ShotDev as its own app and asks for Screen Recording in its name.
        if [ $# -gt 0 ]; then open "$debug_app" --args "$@"; else open "$debug_app"; fi
        echo "Running $debug_app. Stop it with make stop."
        ;;
    stop) stop ;;
    status) status ;;
    *)
        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
        exit 2
        ;;
esac
