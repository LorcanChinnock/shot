import json, sys
for path in sys.argv[1:]:
    text = open(path).read()
    header, _, body = text.partition("\n")
    try:
        d = json.loads(body)
    except Exception as e:
        print("unparsed", path, e); print(text[:4000]); continue
    print("=" * 30, path)
    print("proc", d.get("procName"), "os", d.get("osVersion"))
    print("exception", json.dumps(d.get("exception")), json.dumps(d.get("termination")))
    print("asi", json.dumps(d.get("asi")))
    print("vmregion", d.get("vmRegionInfo"))
    imgs = d.get("usedImages", [])
    ft = d.get("faultingThread")
    for i, t in enumerate(d.get("threads", [])):
        trig = t.get("triggered") or i == ft
        n = 80 if trig else 14
        print("--- thread", i, "TRIGGERED" if trig else "", t.get("name", ""), t.get("queue", ""))
        for f in t.get("frames", [])[:n]:
            img = imgs[f["imageIndex"]].get("name", "?") if f.get("imageIndex") is not None and f["imageIndex"] < len(imgs) else "?"
            print("   ", img, f.get("symbol", hex(f.get("imageOffset", 0))), f.get("symbolLocation", ""))
