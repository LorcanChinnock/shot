import sys
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 1260
# Scale multiplies the canvas, the window width and the shadow, so 2 gives a 3200 × 2000 image that is sharp on Retina.
# Canvas (WxH, before scaling) defaults to 1600x1000; the welcome shot uses 1240x940.
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1
cw, ch = (int(v) for v in (sys.argv[5] if len(sys.argv) > 5 else '1600x1000').split('x'))
W, H, width = round(cw * scale), round(ch * scale), round(width * scale)
top = (138, 127, 120); bot = (59, 63, 83)
bg = Image.new('RGB', (W, H))
px = bg.load()
for y in range(H):
    t = y / H
    c = tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(W):
        px[x, y] = c
win = Image.open(src).convert('RGBA')
h = round(win.height * width / win.width)
if win.size != (width, h):
    win = win.resize((width, h), Image.LANCZOS)
x = (W - width) // 2
y = max(round(30 * scale), (H - h) // 2 - round(19 * scale))
shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
a = win.split()[3].point(lambda v: int(v * 0.45))
blk = Image.new('RGBA', win.size, (0, 0, 0, 255))
blk.putalpha(a)
shadow.paste(blk, (x, y + round(22 * scale)), blk)
shadow = shadow.filter(ImageFilter.GaussianBlur(26 * scale))
bg = Image.alpha_composite(bg.convert('RGBA'), shadow)
bg.alpha_composite(win, (x, y))
bg.convert('RGB').save(out)
