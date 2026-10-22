import json, sys
text = open(sys.argv[1]).read()
_, _, body = text.partition("\n")
d = json.loads(body)
print("=" * 20, sys.argv[1], d.get("procName"), json.dumps(d.get("exception")))
imgs = d.get("usedImages", [])
for i, t in enumerate(d.get("threads", [])):
    trig = t.get("triggered")
    print("--- thread", i, "CRASHED" if trig else "", t.get("name", ""), t.get("queue", ""))
    for f in t.get("frames", [])[: None if trig else 15]:
        ix = f.get("imageIndex", 10**9)
        print("   ", imgs[ix].get("name", "?") if ix < len(imgs) else "?", f.get("symbol", hex(f.get("imageOffset", 0))), f.get("symbolLocation", ""))
