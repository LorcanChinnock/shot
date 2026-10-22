import json, sys
running = {}
last = None
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except Exception:
        continue
    payload = record.get("payload", {})
    kind = payload.get("kind")
    test = payload.get("testID")
    if kind == "testStarted":
        running[test] = payload.get("instant", {}).get("absolute")
    elif kind == "testEnded" or kind == "testSkipped":
        running.pop(test, None)
    last = payload.get("instant", {}).get("absolute") or last
print("last event at", last)
for test, at in sorted(running.items(), key=lambda kv: kv[1] or 0):
    print("STILL RUNNING since", at, test)
