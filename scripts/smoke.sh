#!/bin/sh
# Launches build/ShotDev.app, checks it is still running after a few seconds with no crash report, then quits it. It
# catches startup failures such as a bad entitlement, a missing resource or a Sparkle misconfiguration. It needs no
# Screen Recording permission, since nothing is captured. Build the app first with `make bundle`.
set -eu
cd "$(dirname "$0")/.."

app=build/ShotDev.app
seconds=${SMOKE_SECONDS:-8}
reports="$HOME/Library/Logs/DiagnosticReports"

[ -d "$app" ] || { echo "error: $app not found; run make bundle first" >&2; exit 1; }
pkill -x ShotDev 2>/dev/null || true

"$app/Contents/MacOS/ShotDev" &
pid=$!
sleep "$seconds"

if ! kill -0 "$pid" 2>/dev/null; then
    echo "error: ShotDev exited within $seconds seconds" >&2
    wait "$pid" || echo "exit status $?" >&2
    cat "$reports"/ShotDev* 2>/dev/null || true
    exit 1
fi

kill "$pid"
wait "$pid" 2>/dev/null || true
if ls "$reports"/ShotDev* >/dev/null 2>&1; then
    echo "error: ShotDev left a crash report" >&2
    cat "$reports"/ShotDev*
    exit 1
fi
echo "ShotDev stayed up for $seconds seconds"
