#!/bin/sh
# Runs `make test` with the rest as extra xcodebuild arguments, and says why when the tests die or stop moving. It
# keeps a result bundle, the .xcresult Xcode opens with every test's output and any crash in it, at
# $RUNNER_TEMP/Shot.xcresult. When no test has started or ended for five minutes, it prints the tests still running
# and samples the test process, once, and lets the run go on. When the run fails it prints the crash reports
# (scripts/crash-reports.sh).
# Usage: TEST_ACTION=test-without-building scripts/ci-test.sh [xcodebuild arguments]
set -u
cd "$(dirname "$0")/.."

temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
log="$temp/shot-test.log"
results="$temp/Shot.xcresult"
rm -rf "$log" "$results"
: > "$log"

# Swift Testing prints "◇ Test name() started." and then a line saying it passed, failed or was skipped.
running_tests() {
    python3 -I - "$log" <<'PY'
import re, sys

running = {}
for line in open(sys.argv[1], errors="replace"):
    # A test's name ends at its parameter list, or is a quoted display name; a parameterised test's end line adds
    # "with N test cases" after it.
    started = re.search(r'Test ("[^"]*"|\S+\)) started\.', line)
    ended = re.search(r'Test ("[^"]*"|\S+\)) .*?(passed|failed|skipped)', line)
    if started:
        running[started.group(1)] = True
    elif ended:
        running.pop(ended.group(1), None)
for test in running:
    print("Still running:", test)
PY
}

watch_for_a_stall() {
    size=-1
    still=0
    while sleep 10; do
        now=$(stat -f %z "$log" 2>/dev/null || echo 0)
        if [ "$now" = "$size" ]; then
            still=$((still + 10))
        else
            still=0
            size=$now
        fi
        if [ "$still" -ge 300 ]; then
            echo "::warning::No test has started or ended for five minutes."
            running_tests
            for pid in $(pgrep -x xctest); do
                echo "=== sample of $(ps -o command= -p "$pid")"
                sample "$pid" 3 -file "$temp/shot-test-sample-$pid.txt" >/dev/null 2>&1 && cat "$temp/shot-test-sample-$pid.txt"
            done
            return
        fi
    done
}

watch_for_a_stall &
watcher=$!
# The pipe hides make's exit status, so it's written to a file.
{ make test TEST_ACTION="${TEST_ACTION:-test}" ARGS="$* -resultBundlePath $results" 2>&1; echo $? > "$temp/shot-test-status"; } | tee "$log"
status=$(cat "$temp/shot-test-status")
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null
if [ "$status" -ne 0 ]; then
    # A process that died mid-test leaves a test started and never ended; only then is a crash report on its way.
    interrupted=$(running_tests)
    [ -z "$interrupted" ] || echo "$interrupted"
    CRASH_REPORT_WAIT=$([ -n "$interrupted" ] && echo 90 || echo 0) \
        CRASH_REPORT_DIR="$temp/crash-reports" scripts/crash-reports.sh
fi
exit "$status"
