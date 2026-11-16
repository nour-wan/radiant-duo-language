"""Render the website's leaf logo (public/favicon.svg) to PNG app-icon sources.

Run with the backend venv (has Pillow):
    ../backend/.venv/Scripts/python tool/make_icons.py
Outputs assets/icon/*.png, used by flutter_launcher_icons and flutter_native_splash.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

GREEN = (37, 79, 61, 255)  # #254f3d
CREAM = (243, 234, 219, 255)  # #f3eadb
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"

# M17 41c9-2 16-9 18-23 9 6 14 16 10 25-4 9-17 10-24 4 7-2 13-7 17-15-5 5-11 9-21 9Z
CURVES = [(9, -2, 16, -9, 18, -23), (9, 6, 14, 16, 10, 25), (-4, 9, -17, 10, -24, 4), (7, -2, 13, -7, 17, -15), (-5, 5, -11, 9, -21, 9)]


def leaf_points(scale, ox=0.0, oy=0.0, steps=60):
    x, y = 17.0, 41.0
    pts = [(x, y)]
    for c1x, c1y, c2x, c2y, ex, ey in CURVES:
        p0, p1, p2, p3 = (x, y), (x + c1x, y + c1y), (x + c2x, y + c2y), (x + ex, y + ey)
        for i in range(1, steps + 1):
            t = i / steps
            mt = 1 - t
            px = mt**3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t**3 * p3[0]
            py = mt**3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t**3 * p3[1]
            pts.append((px, py))
        x, y = p3
    # The leaf spans x 17..45, y 18..53 in the 64-unit box; centre it.
    cx, cy = 31.5, 36.0
    return [((px - cx) * scale + ox, (py - cy) * scale + oy) for px, py in pts]


def render(size, leaf_ratio, background=None, rounded=False, leaf_color=CREAM):
    big = size * 4  # supersample for smooth edges
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        if rounded:
            d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 14 / 64), fill=background)
        else:
            d.rectangle([0, 0, big, big], fill=background)
    scale = big * leaf_ratio / 36.0  # leaf height ≈ 36 units
    d.polygon(leaf_points(scale, big / 2, big / 2), fill=leaf_color)
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    render(1024, 0.62, GREEN).save(OUT / "icon.png")  # legacy square icon
    render(1024, 0.62, GREEN, rounded=True).save(OUT / "icon_rounded.png")
    render(1024, 0.40).save(OUT / "foreground.png")  # adaptive icon (safe zone)
    render(1024, 0.40, leaf_color=(255, 255, 255, 255)).save(OUT / "monochrome.png")
    render(768, 0.55, leaf_color=CREAM).save(OUT / "splash.png")  # leaf on green splash background
    admin = render(1024, 0.62, GREEN)
    d = ImageDraw.Draw(admin)
    d.ellipse([700, 700, 980, 980], fill=(180, 70, 43, 255))  # small badge to tell the admin app apart
    d.rounded_rectangle([780, 800, 900, 880], radius=12, fill=CREAM)
    d.rectangle([800, 760, 880, 805], outline=CREAM, width=18)
    admin.save(OUT / "admin_icon.png")
    admin_fg = render(1024, 0.36)
    d = ImageDraw.Draw(admin_fg)
    d.ellipse([610, 610, 790, 790], fill=(180, 70, 43, 255))
    d.rounded_rectangle([660, 680, 740, 735], radius=8, fill=CREAM)
    d.rectangle([673, 650, 727, 683], outline=CREAM, width=12)
    admin_fg.save(OUT / "admin_foreground.png")
    print("icons written to", OUT)


if __name__ == "__main__":
    sys.exit(main())
