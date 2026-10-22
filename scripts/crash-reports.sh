#!/bin/sh
# Prints the crash reports the test run left: each thread's stack, the crashed one in full. A test process that dies on
# a signal leaves only "exited with unexpected signal code 11" in the log, so scripts/ci-test.sh runs this when the
# tests fail, to get the stack for the next time it happens. Reports from other processes are listed by name only.
set -eu

found=0
for dir in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
    [ -d "$dir" ] || continue
    for report in "$dir"/*.ips; do
        [ -f "$report" ] || continue
        case "$(basename "$report")" in
        swiftpm-testing-helper* | ShotCorePackageTests* | xctest*)
            found=1
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
[ "$found" = 1 ] || echo "No crash report from a test process."
