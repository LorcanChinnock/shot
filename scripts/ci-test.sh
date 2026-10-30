#!/bin/sh
# Runs `make <target>` with the rest as its swift test flags, and says why when the tests die or stop moving. A test
# process that crashes leaves only "exited with unexpected signal code 11" in the log, and one that hangs leaves nothing
# until the job's time limit, since swift test buffers its output. So the tests also write Swift Testing's event stream:
# when no test has started or ended for five minutes, this prints the tests still running and samples the test process,
# once, and lets the run go on. When the run fails it prints the crash reports (scripts/crash-reports.sh).
# Usage: scripts/ci-test.sh test --skip-build
set -u

target="${1:?usage: scripts/ci-test.sh <make target> [swift test flags]}"
shift
events="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/shot-test-events.jsonl"
rm -f "$events"
running_tests() {
    python3 -I - "$events" <<'EOF'
import json, sys

running = {}
for line in open(sys.argv[1]):
    try:
        payload = json.loads(line).get("payload", {})
    except ValueError:
        continue
    if payload.get("kind") == "testStarted":
        running[payload.get("testID")] = True
    elif payload.get("kind") in ("testEnded", "testSkipped"):
        running.pop(payload.get("testID"), None)
for test in running:
    print("Still running:", test)
EOF
}

watch_for_a_stall() {
    size=-1
    still=0
    while sleep 10; do
        now=$(stat -f %z "$events" 2>/dev/null || echo 0)
        if [ "$now" = "$size" ]; then
            still=$((still + 10))
        else
            still=0
            size=$now
        fi
        if [ "$still" -ge 300 ]; then
            echo "::warning::No test has started or ended for five minutes."
            running_tests
            for pid in $(pgrep -f swiftpm-testing-helper); do
                echo "=== sample of $(ps -o command= -p "$pid")"
                sample "$pid" 3 -file "${events%.jsonl}-$pid.txt" >/dev/null 2>&1 && cat "${events%.jsonl}-$pid.txt"
            done
            return
        fi
    done
}

watch_for_a_stall &
watcher=$!
make "$target" ARGS="$* --event-stream-output-path $events"
status=$?
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null
if [ "$status" -ne 0 ]; then
    # A process that died mid-test leaves a test started and never ended; only then is a crash report on its way.
    interrupted=$([ -f "$events" ] && running_tests)
    [ -z "$interrupted" ] || echo "$interrupted"
    CRASH_REPORT_WAIT=$([ -n "$interrupted" ] && echo 90 || echo 0) \
        CRASH_REPORT_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/crash-reports" scripts/crash-reports.sh
fi
exit "$status"
