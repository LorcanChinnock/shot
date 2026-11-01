import sys
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
width = int(sys.argv[3]) if len(sys.argv) > 3 else 1260
top = (138, 127, 120); bot = (59, 63, 83)
bg = Image.new('RGB', (1600, 1000))
px = bg.load()
for y in range(1000):
    t = y / 1000
    c = tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(1600):
        px[x, y] = c
win = Image.open(src).convert('RGBA')
h = round(win.height * width / win.width)
win = win.resize((width, h), Image.LANCZOS)
x = (1600 - width) // 2
y = max(30, (1000 - h) // 2 - 19)
shadow = Image.new('RGBA', (1600, 1000), (0, 0, 0, 0))
a = win.split()[3].point(lambda v: int(v * 0.45))
blk = Image.new('RGBA', win.size, (0, 0, 0, 255))
blk.putalpha(a)
shadow.paste(blk, (x, y + 22), blk)
shadow = shadow.filter(ImageFilter.GaussianBlur(26))
bg = Image.alpha_composite(bg.convert('RGBA'), shadow)
bg.alpha_composite(win, (x, y))
bg.convert('RGB').save(out)
