#!/usr/bin/env python3
"""Draws the app icon (ghost inside a disk ring on green) into Resources/AppIcon.iconset.
Flat layers only: on macOS 26 the system adds the glass highlight and shadow itself."""
import os
from PIL import Image, ImageDraw

S = 4096                      # supersampled canvas (4x of 1024)
k = S / 1024
def q(v): return int(round(v * k))

def vgradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Body: 824×824 squircle on the 1024 grid.
box = (q(100), q(100), q(924), q(924))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=q(185), fill=255)
img.paste(vgradient((S, S), (100, 210, 168), (15, 143, 110)).convert("RGBA"), (0, 0), mask)

d = ImageDraw.Draw(img)

# Disk ring: used part white, free part yellow, centred on the icon.
cx, cy, r, w = 512, 512, 312, 31
ring = (q(cx - r), q(cy - r), q(cx + r), q(cy + r))
d.arc(ring, start=-90, end=-90 + 360 * 0.72, fill=(255, 255, 255, 150), width=q(w))
d.arc(ring, start=-90 + 360 * 0.745, end=-90 + 360 * 0.975, fill=(255, 214, 10, 255), width=q(w))

# Ghost: dome + body + wavy hem, from a 16×20 design (x 4..20, y 2..22), scale 20 → 320×400 px.
s, ox, oy = 20, 512 - 12 * 20, 520 - 12 * 20
def p(x, y): return (q(ox + x * s), q(oy + y * s))

def bezier(p0, p1, p2, p3, n=40):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return pts

pts = [p(4, 22), p(4, 10)]
pts += bezier(p(4, 10), p(4, 5.58), p(7.58, 2), p(12, 2))[1:]
pts += bezier(p(12, 2), p(16.42, 2), p(20, 5.58), p(20, 10))[1:]
pts += [p(20, 22), p(17, 19), p(14.5, 21.5), p(12, 19), p(9.5, 21.5), p(7, 19)]
d.polygon(pts, fill=(255, 255, 255, 255))

eye = (11, 77, 60, 255)
for ex in (9, 15):
    x0, y0 = p(ex - 1.2, 8.6)
    x1, y1 = p(ex + 1.2, 11.8)
    d.ellipse((x0, y0, x1, y1), fill=eye)
mx0, my0 = p(11, 12.6)
mx1, my1 = p(13, 14.6)
d.chord((mx0, my0, mx1, my1), start=0, end=180, fill=eye)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "AppIcon.iconset")
os.makedirs(out, exist_ok=True)
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base * scale
        name = f"icon_{base}x{base}" + ("@2x" if scale == 2 else "") + ".png"
        img.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
img.resize((1024, 1024), Image.LANCZOS).save("/tmp/poltergeist-icon.png")
print("icon written")
