#!/usr/bin/env python3
"""Generates the pixel-art dog frames.

Run:  python3 tools/gen_sprites.py
Writes Sources/RaicodePet/DogSprites.swift (the grids the app renders) and
tools/preview.png (every frame, scaled up, for review).

Once you like the art you can also edit the grids in DogSprites.swift by hand —
but re-running this script overwrites them.
"""
import math
import os

W, H = 32, 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Legend — keep in sync with the palette in DogSprites.swift
PALETTE = {
    "o": (58, 38, 30),     # outline
    "t": (226, 166, 102),  # tan coat
    "d": (184, 118, 66),   # dark tan (ears, shading)
    "c": (252, 236, 210),  # cream (muzzle, belly, paws)
    "k": (34, 24, 22),     # eyes / nose
    "w": (255, 255, 255),  # eye highlight
    "p": (240, 120, 140),  # tongue
    "h": (246, 168, 160),  # cheek blush
    "r": (214, 58, 52),    # collar
    "y": (250, 204, 72),   # tag
    "z": (150, 170, 220),  # sleep z's / effects
}


class Canvas:
    def __init__(self):
        self.g = [["." for _ in range(W)] for _ in range(H)]

    def set(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = c

    def get(self, x, y):
        return self.g[y][x] if 0 <= x < W and 0 <= y < H else "."

    def ellipse(self, cx, cy, rx, ry, c, outline=True, angle=0.0):
        """Filled ellipse; with outline=True a 1px outline ring is drawn first."""
        ca, sa = math.cos(angle), math.sin(angle)

        def inside(x, y, grow):
            dx, dy = x - cx, y - cy
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            return (u / (rx + grow)) ** 2 + (v / (ry + grow)) ** 2 <= 1.0

        if outline:
            for y in range(H):
                for x in range(W):
                    if inside(x, y, 1.0) and not inside(x, y, 0):
                        self.g[y][x] = "o"
        for y in range(H):
            for x in range(W):
                if inside(x, y, 0):
                    self.g[y][x] = c

    def px(self, pts, c):
        for x, y in pts:
            self.set(x, y, c)

    def rows(self):
        return ["".join(r) for r in self.g]


# ---------- parts ----------

def ears(cv, cx, cy, mood):
    if mood == "perk":   # alert, ears lifted
        cv.ellipse(cx - 8, cy - 4, 2.6, 4.0, "d", angle=0.5)
        cv.ellipse(cx + 8, cy - 4, 2.6, 4.0, "d", angle=-0.5)
    elif mood == "flat":  # sad, ears drooping low
        cv.ellipse(cx - 9, cy + 2, 2.4, 4.6, "d", angle=-0.35)
        cv.ellipse(cx + 9, cy + 2, 2.4, 4.6, "d", angle=0.35)
    elif mood == "flap":  # mid-bounce
        cv.ellipse(cx - 9, cy - 2, 2.6, 4.4, "d", angle=0.9)
        cv.ellipse(cx + 9, cy - 2, 2.6, 4.4, "d", angle=-0.9)
    else:                 # normal floppy
        cv.ellipse(cx - 8.5, cy, 2.6, 4.6, "d", angle=0.25)
        cv.ellipse(cx + 8.5, cy, 2.6, 4.6, "d", angle=-0.25)


def head(cv, cx, cy, eyes="open", mouth="smile", ear="normal", blush=False):
    ears(cv, cx, cy, ear)
    cv.ellipse(cx, cy, 7.6, 6.4, "t")
    # muzzle
    cv.ellipse(cx, cy + 3.2, 3.6, 2.4, "c", outline=False)
    # forehead blaze
    cv.px([(cx, cy - 5), (cx, cy - 4), (cx, cy - 3)], "c")
    # nose
    cv.px([(cx - 1, cy + 1.4), (cx, cy + 1.4), (cx + 1, cy + 1.4), (cx, cy + 2.4)], "k")

    ex = 3.6
    ey = cy - 0.6
    for side in (-1, 1):
        x = cx + side * ex
        if eyes == "open":
            x0 = int(round(x - 0.5))
            cv.px([(x0, ey), (x0 + 1, ey), (x0, ey + 1), (x0 + 1, ey + 1)], "k")
            cv.set(x0, ey, "w")
        elif eyes == "closed":
            cv.px([(x - 1, ey + 1), (x, ey + 1), (x + 1, ey + 1)], "k")
        elif eyes == "happy":
            cv.px([(x - 1, ey + 1), (x, ey), (x + 1, ey + 1)], "k")
        elif eyes == "sad":
            cv.px([(x, ey), (x, ey + 1)], "k")
            # slanted brow
            cv.px([(x - side, ey - 2), (x, ey - 1.6)], "o")

    if blush:
        cv.set(cx - 5, cy + 2, "h")
        cv.set(cx + 5, cy + 2, "h")

    my = cy + 4.4
    if mouth == "smile":
        cv.px([(cx - 1, my), (cx + 1, my)], "o")
    elif mouth == "tongue":
        cv.px([(cx - 1, my), (cx + 1, my)], "o")
        cv.px([(cx, my), (cx, my + 1), (cx + 1, my + 1)], "p")
    elif mouth == "open":   # yawn / bark
        cv.px([(cx - 1, my), (cx, my), (cx + 1, my), (cx - 1, my + 1), (cx + 1, my + 1)], "o")
        cv.px([(cx, my + 1)], "p")
    elif mouth == "frown":
        cv.px([(cx - 1, my + 1), (cx, my), (cx + 1, my + 1)], "o")


def collar(cv, cx, y):
    for x in range(int(cx - 4), int(cx + 5)):
        if cv.get(x, y) != ".":
            cv.set(x, y, "r")
    cv.set(cx, y + 1, "y")


def tail(cv, x, y, angle):
    cv.ellipse(x, y, 1.6, 3.6, "t", angle=angle)
    tip_x = x + math.sin(angle) * 3.2
    tip_y = y - math.cos(angle) * 3.2
    cv.set(tip_x, tip_y, "c")


def sitting(cx=16, dy=0, eyes="open", mouth="smile", ear="normal", tail_a=0.5,
            paw="down", blush=False, bob=0):
    cv = Canvas()
    by = 23 + dy
    tail(cv, cx + 7.5, by + 1, tail_a)
    # body
    cv.ellipse(cx, by, 6.6, 6.2, "t")
    cv.ellipse(cx, by + 1.2, 3.6, 4.2, "c", outline=False)
    # paws
    if paw == "raised":
        cv.ellipse(cx - 3.2, by + 5.6, 2.0, 1.4, "c")
        cv.ellipse(cx + 5.0, by - 1.4, 1.8, 1.8, "c")   # waving paw beside chest
    elif paw == "left":
        cv.ellipse(cx - 3.2, by + 4.8, 2.0, 1.4, "c")
        cv.ellipse(cx + 3.2, by + 5.8, 2.0, 1.4, "c")
    elif paw == "right":
        cv.ellipse(cx - 3.2, by + 5.8, 2.0, 1.4, "c")
        cv.ellipse(cx + 3.2, by + 4.8, 2.0, 1.4, "c")
    else:
        cv.ellipse(cx - 3.2, by + 5.6, 2.0, 1.4, "c")
        cv.ellipse(cx + 3.2, by + 5.6, 2.0, 1.4, "c")
    head(cv, cx, 10 + dy + bob, eyes=eyes, mouth=mouth, ear=ear, blush=blush)
    collar(cv, cx, 17 + dy + bob)
    return cv


def sleeping(z_phase=0, breathe=0):
    cv = Canvas()
    # tail curled in front
    cv.ellipse(25, 28, 4.2, 1.6, "t", angle=-0.15)
    # body lying
    cv.ellipse(19.5, 25 - breathe * 0.4, 9.6, 4.8 + breathe * 0.4, "t")
    cv.ellipse(21.5, 26.5, 5.2, 2.2, "c", outline=False)
    # front paws stretched forward under head
    cv.ellipse(8.5, 29, 2.4, 1.4, "c")
    cv.ellipse(12.5, 29.4, 2.4, 1.4, "c")
    # head resting low on the left
    head(cv, 11, 22, eyes="closed", mouth="smile", ear="normal", blush=True)
    collar(cv, 11, 29)
    # floating z's
    zs = [(21, 12), (24, 7), (27, 2)]
    for i, (zx, zy) in enumerate(zs):
        if (i + z_phase) % 3 == 2:
            continue
        size = 2 + (i > 0)
        for dx in range(size + 1):
            cv.set(zx + dx, zy, "z")
            cv.set(zx + dx, zy + size, "z")
        for d in range(size + 1):
            cv.set(zx + size - d, zy + d, "z")
    return cv


def add_sweat(cv, x, y):
    cv.px([(x, y), (x, y + 1), (x - 1, y + 1)], "z")


def add_lines(cv, phase):
    # speed lines left of the dog
    y0 = 20 + phase
    for i, y in enumerate((y0, y0 + 3, y0 + 6)):
        for dx in range(2 + (i % 2)):
            cv.set(2 + dx, y, "z")


def add_sparkle(cv, x, y):
    cv.px([(x, y - 1), (x - 1, y), (x, y), (x + 1, y), (x, y + 1)], "y")


# ---------- frames per state ----------

def frames():
    f = {}
    f["idle"] = [sleeping(0, 0).rows(), sleeping(1, 1).rows(), sleeping(2, 0).rows()]
    f["stretch"] = [
        sitting(eyes="closed", mouth="smile").rows(),
        sitting(eyes="closed", mouth="open", ear="perk").rows(),
        sitting(eyes="open", mouth="smile").rows(),
    ]
    w = []
    for i, (paw, bob, ear) in enumerate([("left", 0, "normal"), ("down", -1, "flap"),
                                         ("right", 0, "normal"), ("down", -1, "flap")]):
        cv = sitting(eyes="open", mouth="tongue", ear=ear, paw=paw, bob=bob,
                     tail_a=0.3 if i % 2 else 0.8)
        add_lines(cv, i % 2)
        w.append(cv.rows())
    f["working"] = w
    f["waiting"] = [
        sitting(eyes="open", mouth="open", ear="perk", paw="raised", tail_a=0.4).rows(),
        sitting(dy=-1, eyes="open", mouth="smile", ear="perk", paw="raised", tail_a=0.9).rows(),
    ]
    d = []
    for a in (0.2, 0.8, 1.2, 0.8):
        cv = sitting(eyes="happy", mouth="tongue", tail_a=a, blush=True)
        d.append(cv.rows())
    add_sparkle_rows(d)
    f["done"] = d
    fl = []
    for i in range(2):
        cv = sitting(dy=i, eyes="sad", mouth="frown", ear="flat", tail_a=1.6)
        add_sweat(cv, 24, 6 + i)
        fl.append(cv.rows())
    f["failed"] = fl
    return f


def add_sparkle_rows(frame_rows):
    for i, rows in enumerate(frame_rows):
        g = [list(r) for r in rows]
        pts = [(4, 6), (27, 4)] if i % 2 == 0 else [(5, 3), (28, 8)]
        for x, y in pts:
            for (dx, dy) in [(0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)]:
                if g[y + dy][x + dx] == ".":
                    g[y + dy][x + dx] = "y"
        frame_rows[i] = ["".join(r) for r in g]


# ---------- output ----------

ORDER = ["idle", "stretch", "working", "waiting", "done", "failed"]


def write_swift(f):
    out = []
    out.append("// Generated by tools/gen_sprites.py — edit there, or tweak the grids below by hand.")
    out.append("// One character per pixel. Legend:")
    for k, v in PALETTE.items():
        out.append(f"//   {k}  rgb{v}")
    out.append("//   .  transparent")
    out.append("")
    out.append("enum DogSprites {")
    out.append("    static let palette: [Character: (UInt8, UInt8, UInt8)] = [")
    for k, (r, g, b) in PALETTE.items():
        out.append(f'        "{k}": ({r}, {g}, {b}),')
    out.append("    ]")
    out.append("")
    out.append("    static let frames: [String: [[String]]] = [")
    for name in ORDER:
        out.append(f'        "{name}": [')
        for rows in f[name]:
            out.append("            [")
            for r in rows:
                out.append(f'                "{r}",')
            out.append("            ],")
        out.append("        ],")
    out.append("    ]")
    out.append("}")
    path = os.path.join(ROOT, "Sources", "RaicodePet", "DogSprites.swift")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


def write_preview(f, scale=6):
    from PIL import Image, ImageDraw
    cols = max(len(v) for v in f.values())
    pad = 8
    label_w = 90
    img = Image.new("RGB", (label_w + cols * (W * scale + pad) + pad,
                            len(ORDER) * (H * scale + pad) + pad), (236, 238, 242))
    dr = ImageDraw.Draw(img)
    for r, name in enumerate(ORDER):
        y0 = pad + r * (H * scale + pad)
        dr.text((8, y0 + H * scale // 2 - 6), name, fill=(40, 40, 40))
        for c, rows in enumerate(f[name]):
            x0 = label_w + c * (W * scale + pad)
            dr.rectangle([x0, y0, x0 + W * scale - 1, y0 + H * scale - 1], fill=(255, 255, 255))
            for y, row in enumerate(rows):
                for x, ch in enumerate(row):
                    if ch in PALETTE:
                        dr.rectangle([x0 + x * scale, y0 + y * scale,
                                      x0 + x * scale + scale - 1, y0 + y * scale + scale - 1],
                                     fill=PALETTE[ch])
    img.save(os.path.join(ROOT, "tools", "preview.png"))


if __name__ == "__main__":
    fr = frames()
    write_swift(fr)
    write_preview(fr)
    print("ok:", {k: len(v) for k, v in fr.items()})
