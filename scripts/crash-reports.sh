#!/bin/sh
# Prints the crash reports the test run left: each thread's stack, the crashed one in full. A test process that dies on
# a signal leaves only "exited with unexpected signal code 11" in the log, so scripts/ci-test.sh runs this when the
# tests fail, to get the stack for the next time it happens. Reports from other processes are listed by name only.
set -eu

# ReportCrash writes the report some seconds after the process dies, so the run that just failed has none yet. Wait for
# one, up to $CRASH_REPORT_WAIT seconds (default 0), when the caller knows a process crashed. Copies go to
# $CRASH_REPORT_DIR, which the workflow uploads.
wait_for=${CRASH_REPORT_WAIT:-0}
keep=${CRASH_REPORT_DIR:-}
dirs="$HOME/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports"

has_report() {
    for dir in $dirs; do
        for report in "$dir"/swiftpm-testing-helper* "$dir"/ShotCorePackageTests* "$dir"/xctest*; do
            [ -f "$report" ] && return 0
        done
    done
    return 1
}

waited=0
while ! has_report && [ "$waited" -lt "$wait_for" ]; do
    sleep 3
    waited=$((waited + 3))
done

found=0
for dir in $dirs; do
    [ -d "$dir" ] || continue
    for report in "$dir"/*.ips; do
        [ -f "$report" ] || continue
        case "$(basename "$report")" in
        swiftpm-testing-helper* | ShotCorePackageTests* | xctest*)
            found=1
            if [ -n "$keep" ]; then
                mkdir -p "$keep"
                cp "$report" "$keep/"
            fi
            python3 -I - "$report" <<'EOF' || echo "Couldn't read $report"
import json, sys

path = sys.argv[1]
_, _, body = open(path).read().partition("\n")
report = json.loads(body)
print(f"=== {path}")
print("process:", report.get("procName"), "OS:", report.get("osVersion", {}).get("train"), report.get("osVersion", {}).get("build"))
print("exception:", json.dumps(report.get("exception")))
if report.get("vmRegionInfo"):
    print("address:", report["vmRegionInfo"])
images = report.get("usedImages", [])
for index, thread in enumerate(report.get("threads", [])):
    crashed = thread.get("triggered", False)
    print(f"--- thread {index}{' CRASHED' if crashed else ''} {thread.get('name', '')} {thread.get('queue', '')}")
    for frame in thread.get("frames", [])[: None if crashed else 12]:
        image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", len(images)) < len(images) else "?"
        print("   ", image, frame.get("symbol", hex(frame.get("imageOffset", 0))), frame.get("symbolLocation", ""))
EOF
            ;;
        *)
            echo "Other report: $report"
            ;;
        esac
    done
done
if [ "$found" != 1 ]; then
    echo "No crash report from a test process after ${waited}s. Reports present:"
    ls -la $dirs 2>&1 || true
fi
