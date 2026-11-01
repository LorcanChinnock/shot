import sys, Quartz
owner = sys.argv[1]
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') == owner and w.get('kCGWindowLayer') == 0:
        b = w['kCGWindowBounds']
        print(w['kCGWindowNumber'], repr(w.get('kCGWindowName')), int(b['Width']), int(b['Height']))
