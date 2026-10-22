#!/bin/bash
# Runs the suite N times. Hang: no new test event for 180 s. Then samples the test process.
set +e
fails=0
for i in $(seq 1 "$1"); do
  rm -f events.jsonl run.log
  swift test --skip-build --skip PerfTests --event-stream-output-path events.jsonl > run.log 2>&1 &
  pid=$!
  size=-1; still=0; hung=0
  while kill -0 $pid 2>/dev/null; do
    sleep 5
    now=$(stat -f %z events.jsonl 2>/dev/null || echo 0)
    if [ "$now" = "$size" ]; then still=$((still+5)); else still=0; size=$now; fi
    if [ $still -ge 180 ]; then hung=1; break; fi
  done
  if [ $hung = 1 ]; then
    echo "iteration $i HUNG"
    python3 -I .github/probe/running.py events.jsonl
    for h in $(pgrep -f swiftpm-testing-helper) $(pgrep -f ShotCorePackageTests); do
      echo "=== sample $h"; ps -o pid,pcpu,rss,command -p $h
      sample $h 3 -file sample-$h.txt >/dev/null 2>&1; cat sample-$h.txt | grep -v "^\s*$" | head -700
    done
    pkill -9 -f swiftpm-testing-helper; kill -9 $pid 2>/dev/null
    fails=$((fails+1)); continue
  fi
  wait $pid; rc=$?
  echo "iteration $i exit $rc"
  if [ $rc -ne 0 ]; then
    fails=$((fails+1))
    python3 -I .github/probe/running.py events.jsonl
    grep -E "signal|✘" run.log | tail -20
  fi
done
echo "FAILS $fails"
