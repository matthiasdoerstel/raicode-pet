#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from the pixel dog's happy pose.

Run:  python3 tools/make_icon.py
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sprites as gs  # noqa: E402

ROOT = gs.ROOT
SIZE = 1024


def squircle_mask(size, radius_ratio=0.225):
    m = Image.new("L", (size, size), 0)
    r = int(size * radius_ratio)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return m


def icon():
    # macOS icon grid: artwork sits in an 824px rounded square centred on a 1024 canvas
    inner = 824
    off = (SIZE - inner) // 2

    bg = Image.new("RGBA", (inner, inner))
    top, bottom = (255, 226, 170), (246, 170, 104)  # warm backdrop so the black dog pops
    d = ImageDraw.Draw(bg)
    for y in range(inner):
        t = y / (inner - 1)
        d.line([(0, y), (inner, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))

    rows = gs.sitting(gs.griffon_head, eye="happy", mouth="tongue", tail_a=0.8, blush=True, belly=False).rows()
    dog = Image.new("RGBA", (gs.W, gs.H), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in gs.GRIFFON:
                dog.putpixel((x, y), gs.GRIFFON[ch] + (255,))
    scale = 19  # 32px * 19 = 608px
    dog = dog.resize((gs.W * scale, gs.H * scale), Image.NEAREST)

    # soft floor shadow
    shadow = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([inner * 0.22, inner * 0.80, inner * 0.78, inner * 0.88], fill=(120, 60, 20, 70))
    bg = Image.alpha_composite(bg, shadow)
    bg.alpha_composite(dog, ((inner - dog.width) // 2, inner - dog.height - 70))

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(bg, (off, off), squircle_mask(inner))
    return canvas


def main():
    base = icon()
    iconset = os.path.join(ROOT, "build", "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for s in (16, 32, 128, 256, 512):
        for mult in (1, 2):
            px = s * mult
            name = f"icon_{s}x{s}{'@2x' if mult == 2 else ''}.png"
            base.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
    out = os.path.join(ROOT, "Resources", "AppIcon.icns")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    base.save(os.path.join(ROOT, "tools", "icon-preview.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
