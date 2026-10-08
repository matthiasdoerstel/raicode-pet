#!/usr/bin/env python3
"""Generates the built-in pixel-art pets.

Run:  python3 tools/gen_sprites.py
Writes Sources/RaicodePet/PixelSprites.swift (the grids the app renders) and
tools/preview.png (every frame of every pet, scaled up, for review).

You can also tweak the grids in PixelSprites.swift by hand — but re-running
this script overwrites them.
"""
import math
import os

W, H = 32, 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Effect pixels never get an outline (sparkles, z's, sweat drops).
EFFECTS = set("zyY")

# ---------- palettes (one per character) ----------

GRIFFON = {
    "o": (14, 12, 18),     # outline
    "t": (62, 58, 70),     # black coat, lifted a touch so details read
    "d": (34, 31, 40),     # ears, inner shading
    "m": (128, 120, 138),  # beard mask / moustache / brows (rough hair highlights)
    "e": (96, 60, 38),     # warm brown eye
    "k": (6, 6, 8),        # pupils / nose
    "w": (255, 255, 255),  # eye shine / teeth
    "p": (240, 120, 140),  # tongue
    "h": (200, 112, 124),  # blush
    "r": (214, 58, 52),    # collar
    "y": (250, 204, 72),   # tag / sparkles
    "z": (150, 170, 220),  # effects
}

GOLDEN = {
    "o": (58, 38, 30),
    "t": (226, 166, 102),
    "d": (184, 118, 66),
    "b": (252, 236, 210),  # cream
    "k": (34, 24, 22),
    "w": (255, 255, 255),
    "p": (240, 120, 140),
    "h": (246, 168, 160),
    "r": (214, 58, 52),
    "y": (250, 204, 72),
    "z": (150, 170, 220),
}

CAT = {
    "o": (74, 42, 30),
    "t": (244, 164, 86),   # ginger
    "d": (212, 114, 52),   # stripes
    "b": (254, 238, 214),  # cream
    "k": (30, 22, 20),
    "g": (120, 196, 96),   # eyes
    "w": (255, 255, 255),
    "p": (244, 132, 152),  # nose, inner ears
    "h": (250, 170, 160),
    "y": (250, 204, 72),
    "z": (150, 170, 220),
}

ROBOT = {
    "o": (42, 48, 66),
    "s": (230, 236, 244),  # shell
    "g": (164, 174, 194),  # panels
    "n": (34, 42, 66),     # screen
    "e": (120, 236, 255),  # eye glow
    "a": (255, 160, 60),   # antenna: waiting
    "G": (96, 214, 124),   # antenna: done
    "R": (240, 92, 82),    # antenna: failed
    "y": (250, 204, 72),   # antenna: working / sparkles
    "Y": (250, 204, 72),
    "w": (255, 255, 255),
    "z": (150, 170, 220),
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

    def shape(self, inside, c, outline=True):
        """Fill every pixel where inside(x, y); optionally ring it with outline first."""
        mask = {(x, y) for y in range(H) for x in range(W) if inside(x, y)}
        if outline:
            for x, y in mask:
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if (nx, ny) not in mask:
                        self.set(nx, ny, "o")
        for x, y in mask:
            self.g[y][x] = c

    def ellipse(self, cx, cy, rx, ry, c, outline=True, angle=0.0):
        ca, sa = math.cos(angle), math.sin(angle)

        def inside(x, y):
            dx, dy = x - cx, y - cy
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            return (u / rx) ** 2 + (v / ry) ** 2 <= 1.0

        self.shape(inside, c, outline)

    def poly(self, pts, c, outline=True):
        def inside(x, y):
            px, py = x, y
            hit = False
            j = len(pts) - 1
            for i in range(len(pts)):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                    hit = not hit
                j = i
            return hit

        self.shape(inside, c, outline)

    def rect(self, x0, y0, x1, y1, c, outline=True, round_corners=False):
        def inside(x, y):
            if not (x0 <= x <= x1 and y0 <= y <= y1):
                return False
            if round_corners and (x in (x0, x1)) and (y in (y0, y1)):
                return False
            return True

        self.shape(inside, c, outline)

    def px(self, pts, c):
        for x, y in pts:
            self.set(x, y, c)

    def finish(self):
        """Outline anything still touching the background (beard fringes, whiskers, …)."""
        add = []
        for y in range(H):
            for x in range(W):
                c = self.g[y][x]
                if c in ".o" or c in EFFECTS:
                    continue
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if self.get(nx, ny) == "." and 0 <= nx < W and 0 <= ny < H:
                        add.append((nx, ny))
        for x, y in add:
            self.g[y][x] = "o"
        return self

    def rows(self):
        return ["".join(r) for r in self.finish().g]


# ---------- shared effects ----------

def zs(cv, phase, spots=((21, 12), (24, 7), (27, 2))):
    for i, (zx, zy) in enumerate(spots):
        if (i + phase) % 3 == 2:
            continue
        size = 2 + (i > 0)
        for dx in range(size + 1):
            cv.set(zx + dx, zy, "z")
            cv.set(zx + dx, zy + size, "z")
        for d in range(size + 1):
            cv.set(zx + size - d, zy + d, "z")


def speed_lines(cv, phase):
    y0 = 20 + phase
    for i, y in enumerate((y0, y0 + 3, y0 + 6)):
        for dx in range(2 + (i % 2)):
            cv.set(1 + dx, y, "z")


def sparkles(cv, i):
    pts = [(3, 6), (28, 4)] if i % 2 == 0 else [(4, 3), (28, 9)]
    for x, y in pts:
        for dx, dy in ((0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)):
            if cv.get(x + dx, y + dy) == ".":
                cv.set(x + dx, y + dy, "y")


def sweat(cv, x, y):
    cv.px([(x, y), (x, y + 1), (x - 1, y + 1), (x, y + 2)], "z")


# ---------- faces ----------

def eyes(cv, cx, ey, kind, spread, size, iris="k"):
    for side in (-1, 1):
        x = cx + side * spread
        x0 = int(round(x - size / 2))
        if kind == "open":
            for dx in range(size):
                for dy in range(size):
                    cv.set(x0 + dx, ey + dy, iris)
            if iris != "k":  # pupil
                cv.set(x0 + size // 2, ey + size // 2, "k")
                if size > 2:
                    cv.set(x0 + size // 2, ey + size // 2 - 1, "k")
            cv.set(x0, ey, "w")
            if size >= 3:
                cv.set(x0 + size - 1, ey + size - 1, "w")
        elif kind == "closed":
            for dx in range(size + 1):
                cv.set(x0 + dx - (side < 0), ey + size - 1, "k")
        elif kind == "happy":
            for dx in range(size + 1):
                d = abs(dx - size / 2)
                cv.set(x0 + dx - (side < 0), ey + size - 1 - (1 if d < 1 else 0) + (0 if d < size / 2 else 0), "k")
        elif kind == "sad":
            for dx in range(size):
                cv.set(x0 + dx, ey + size - 1, "k")
                if size >= 3:
                    cv.set(x0 + dx, ey + size - 2, "k")
            cv.set(x0, ey + size - 2, "w")


def golden_head(cv, cx, cy, eye="open", mouth="smile", ear="normal", blush=False):
    if ear == "perk":
        cv.ellipse(cx - 8, cy - 4, 2.6, 4.0, "d", angle=0.5)
        cv.ellipse(cx + 8, cy - 4, 2.6, 4.0, "d", angle=-0.5)
    elif ear == "flat":
        cv.ellipse(cx - 9, cy + 2, 2.4, 4.6, "d", angle=-0.35)
        cv.ellipse(cx + 9, cy + 2, 2.4, 4.6, "d", angle=0.35)
    elif ear == "flap":
        cv.ellipse(cx - 9, cy - 2, 2.6, 4.4, "d", angle=0.9)
        cv.ellipse(cx + 9, cy - 2, 2.6, 4.4, "d", angle=-0.9)
    else:
        cv.ellipse(cx - 8.5, cy, 2.6, 4.6, "d", angle=0.25)
        cv.ellipse(cx + 8.5, cy, 2.6, 4.6, "d", angle=-0.25)
    cv.ellipse(cx, cy, 7.6, 6.4, "t")
    cv.ellipse(cx, cy + 3.2, 3.6, 2.4, "b", outline=False)
    cv.px([(cx, cy - 5), (cx, cy - 4), (cx, cy - 3)], "b")
    cv.px([(cx - 1, cy + 1.4), (cx, cy + 1.4), (cx + 1, cy + 1.4), (cx, cy + 2.4)], "k")
    eyes(cv, cx, int(round(cy - 0.6)), eye, 3.6, 2)
    if eye == "sad":
        for side in (-1, 1):
            x = cx + side * 3.6
            cv.px([(x - side, cy - 2.6), (x, cy - 2.2)], "o")
    if blush:
        cv.set(cx - 5, cy + 2, "h")
        cv.set(cx + 5, cy + 2, "h")
    my = cy + 4.4
    if mouth == "smile":
        cv.px([(cx - 1, my), (cx + 1, my)], "o")
    elif mouth == "tongue":
        cv.px([(cx - 1, my), (cx + 1, my)], "o")
        cv.px([(cx, my), (cx, my + 1), (cx + 1, my + 1)], "p")
    elif mouth == "open":
        cv.px([(cx - 1, my), (cx, my), (cx + 1, my), (cx - 1, my + 1), (cx + 1, my + 1)], "o")
        cv.px([(cx, my + 1)], "p")
    elif mouth == "frown":
        cv.px([(cx - 1, my + 1), (cx, my), (cx + 1, my + 1)], "o")


def cat_head(cv, cx, cy, eye="open", mouth="smile", ear="normal", blush=False):
    if ear == "perk":
        L, Li = [(cx - 7.5, cy - 1), (cx - 6.5, cy - 10), (cx - 1.5, cy - 5)], [(cx - 6, cy - 3), (cx - 5.8, cy - 7.5), (cx - 3.5, cy - 5)]
    elif ear == "flat":
        L, Li = [(cx - 7, cy - 2), (cx - 10, cy - 6.5), (cx - 3.5, cy - 5.5)], [(cx - 6.5, cy - 3.5), (cx - 8.5, cy - 5.8), (cx - 5, cy - 5)]
    elif ear == "flap":
        L, Li = [(cx - 7.5, cy - 1), (cx - 8.5, cy - 9), (cx - 2, cy - 5)], [(cx - 6.5, cy - 3), (cx - 7.2, cy - 6.8), (cx - 4, cy - 5)]
    else:
        L, Li = [(cx - 7.5, cy - 1), (cx - 7, cy - 9), (cx - 2, cy - 5)], [(cx - 6.2, cy - 3), (cx - 6, cy - 6.8), (cx - 3.8, cy - 5)]
    for side in (-1, 1):
        mirror = (lambda pts: [(cx + (cx - x), y) for x, y in pts]) if side == 1 else (lambda pts: pts)
        cv.poly(mirror(L), "t")
        cv.poly(mirror(Li), "p", outline=False)
    cv.ellipse(cx, cy, 7.8, 6.2, "t")
    # tabby stripes
    cv.px([(cx, cy - 5), (cx, cy - 4), (cx - 2, cy - 5), (cx + 2, cy - 5)], "d")
    cv.px([(cx - 7, cy), (cx - 6, cy), (cx + 6, cy), (cx + 7, cy)], "d")
    cv.ellipse(cx, cy + 3, 3.2, 2.0, "b", outline=False)
    eyes(cv, cx, int(round(cy - 1)), eye, 3.8, 2 if eye != "open" else 3, iris="g")
    if eye == "sad":
        for side in (-1, 1):
            x = cx + side * 3.8
            cv.px([(x - side * 1.5, cy - 3), (x + side * 0.5, cy - 3.6)], "o")
    cv.px([(cx - 1, cy + 1.6), (cx, cy + 1.6), (cx, cy + 2.4)], "p")
    # whiskers
    for side in (-1, 1):
        for i in range(3):
            cv.set(cx + side * (7 + i), cy + 2 + (i == 2) * side * 0, "o")
            cv.set(cx + side * (7 + i), cy + 3.6 + i * 0.5, "o")
    if blush:
        cv.set(cx - 5, cy + 2, "h")
        cv.set(cx + 5, cy + 2, "h")
    my = cy + 3.4
    if mouth in ("smile", "tongue"):
        cv.px([(cx - 2, my), (cx - 1, my + 1), (cx, my), (cx + 1, my + 1), (cx + 2, my)], "o")
        if mouth == "tongue":
            cv.px([(cx, my + 1), (cx, my + 2)], "p")
    elif mouth == "open":
        cv.px([(cx - 1, my), (cx, my), (cx + 1, my), (cx - 1, my + 1), (cx + 1, my + 1), (cx, my + 2)], "o")
        cv.px([(cx, my + 1)], "p")
    elif mouth == "frown":
        cv.px([(cx - 1, my + 1), (cx, my), (cx + 1, my + 1)], "o")


# ---------- bodies ----------

def dog_tail(cv, x, y, angle):
    cv.ellipse(x, y, 1.6, 3.6, "t", angle=angle)
    cv.set(x + math.sin(angle) * 3.2, y - math.cos(angle) * 3.2, "b")


def cat_tail(cv, x, y, curl):
    # a long tail sweeping up, drawn as a chain of round segments
    pts = []
    for i in range(10):
        t = i / 9
        px = x + 2.5 * t + math.sin(t * math.pi) * 1.5
        py = y - 12 * t
        px += curl * math.sin(t * math.pi * 1.4) * 2.2
        pts.append((px, py))
    for px, py in pts:
        cv.ellipse(px, py, 1.4, 1.4, "t")
    for px, py in pts:
        cv.ellipse(px, py, 0.9, 0.9, "t", outline=False)
    cv.set(pts[-1][0], pts[-1][1], "d")
    cv.set(pts[5][0], pts[5][1], "d")


def sitting(head, kind="dog", cx=16, dy=0, eye="open", mouth="smile", ear="normal", tail_a=0.5,
            paw="down", blush=False, bob=0, belly=True):
    cv = Canvas()
    by = 23 + dy
    if kind == "cat":
        cat_tail(cv, cx + 6, by + 4, tail_a)
    else:
        dog_tail(cv, cx + 7.5, by + 1, tail_a)
    cv.ellipse(cx, by, 6.4 if kind == "cat" else 6.6, 6.2, "t")
    if belly:
        cv.ellipse(cx, by + 1.2, 3.4, 4.2, "b", outline=False)
    if kind == "cat":
        cv.px([(cx - 5, by - 1), (cx - 5, by + 1), (cx + 5, by - 1), (cx + 5, by + 1)], "d")
    paw_c = "b" if belly else "t"
    if paw == "raised":
        cv.ellipse(cx - 3.2, by + 5.6, 2.0, 1.4, paw_c)
        cv.ellipse(cx + 5.0, by - 1.4, 1.8, 1.8, paw_c)
    elif paw == "left":
        cv.ellipse(cx - 3.2, by + 4.8, 2.0, 1.4, paw_c)
        cv.ellipse(cx + 3.2, by + 5.8, 2.0, 1.4, paw_c)
    elif paw == "right":
        cv.ellipse(cx - 3.2, by + 5.8, 2.0, 1.4, paw_c)
        cv.ellipse(cx + 3.2, by + 4.8, 2.0, 1.4, paw_c)
    else:
        cv.ellipse(cx - 3.2, by + 5.6, 2.0, 1.4, paw_c)
        cv.ellipse(cx + 3.2, by + 5.6, 2.0, 1.4, paw_c)
    if not belly:  # toe lines on dark paws
        for px_ in (cx - 3.2, cx + 3.2):
            cv.set(px_, by + 6.4, "d")
    head(cv, cx, 10 + dy + bob, eye=eye, mouth=mouth, ear=ear, blush=blush)
    if kind == "dog":
        y = 18 + dy + bob
        for x in range(int(cx - 4), int(cx + 5)):
            if cv.get(x, y) not in ".o":
                cv.set(x, y, "r")
        cv.set(cx, y + 1, "y")
    return cv


def lying(head, kind="dog", z_phase=0, breathe=0, belly=True):
    cv = Canvas()
    if kind == "cat":
        cv.ellipse(23, 28.4, 6.0, 1.4, "t", angle=-0.1)
        cv.px([(20, 28), (24, 28)], "d")
    else:
        cv.ellipse(25, 28, 4.2, 1.6, "t", angle=-0.15)
    cv.ellipse(19.5, 25 - breathe * 0.4, 9.6, 4.8 + breathe * 0.4, "t")
    if belly:
        cv.ellipse(21.5, 26.5, 5.2, 2.2, "b", outline=False)
    if kind == "cat":
        cv.px([(17, 21), (18, 21), (21, 21), (22, 21)], "d")
    paw_c = "b" if belly else "t"
    cv.ellipse(8.5, 29, 2.4, 1.4, paw_c)
    cv.ellipse(12.5, 29.4, 2.4, 1.4, paw_c)
    head(cv, 11, 22, eye="closed", mouth="smile", ear="normal", blush=True)
    zs(cv, z_phase)
    return cv


def animal(head, kind, belly):
    S = lambda **k: sitting(head, kind=kind, belly=belly, **k)
    f = {}
    f["idle"] = [lying(head, kind, 0, 0, belly).rows(), lying(head, kind, 1, 1, belly).rows(),
                 lying(head, kind, 2, 0, belly).rows()]
    f["stretch"] = [S(eye="closed").rows(), S(eye="closed", mouth="open", ear="perk").rows(),
                    S(eye="open").rows()]
    look = []
    for dx in (0, -1, -1, 0, 1, 1, 0):
        cv = S(eye="open", ear="perk", cx=16 + dx)
        look.append(cv.rows())
    f["look"] = look
    w = []
    for i, (paw, bob, ear) in enumerate([("left", 0, "normal"), ("down", -1, "flap"),
                                         ("right", 0, "normal"), ("down", -1, "flap")]):
        cv = S(eye="open", mouth="tongue", ear=ear, paw=paw, bob=bob,
               tail_a=(0.3 if i % 2 else 0.8) if kind != "cat" else (0.6 if i % 2 else -0.6))
        speed_lines(cv, i % 2)
        w.append(cv.rows())
    f["working"] = w
    f["waiting"] = [S(eye="open", mouth="open", ear="perk", paw="raised", tail_a=0.4).rows(),
                    S(dy=-1, eye="open", mouth="smile", ear="perk", paw="raised", tail_a=0.9).rows()]
    d = []
    for i, a in enumerate((0.2, 0.8, 1.2, 0.8) if kind != "cat" else (-0.8, 0, 0.8, 0)):
        cv = S(eye="happy", mouth="tongue", tail_a=a, blush=True)
        sparkles(cv, i)
        d.append(cv.rows())
    f["done"] = d
    fl = []
    for i in range(2):
        cv = S(dy=i, eye="sad", mouth="frown", ear="flat", tail_a=1.6 if kind != "cat" else 1.2)
        sweat(cv, 25, 5 + i)
        fl.append(cv.rows())
    f["failed"] = fl
    return f


# ---------- griffon belge ----------
# Big round head, huge wide-set eyes, tiny upturned nose between them, flat face
# with a beard "bib" and an underbite, bushy brows, small semi-erect ears,
# compact little body.

def griffon_eye(cv, x0, y0, kind):
    """4×4 eye with its top-left pixel at (x0, y0)."""
    if kind in ("open", "wide"):
        shape = [".kk.", "kwek", "keek", ".kk."]
        if kind == "wide":
            shape = ["kkkk", "kwek", "keek", "kkkk"]
        for dy, row in enumerate(shape):
            for dx, ch in enumerate(row):
                if ch != ".":
                    cv.set(x0 + dx, y0 + dy, ch)
    elif kind == "closed":
        cv.px([(x0, y0 + 2), (x0 + 1, y0 + 3), (x0 + 2, y0 + 3), (x0 + 3, y0 + 2)], "k")
    elif kind == "happy":
        cv.px([(x0, y0 + 3), (x0 + 1, y0 + 2), (x0 + 2, y0 + 2), (x0 + 3, y0 + 3)], "k")
    elif kind == "sad":
        for dy, row in enumerate(["....", "kkkk", "kwek", ".kk."]):
            for dx, ch in enumerate(row):
                if ch != ".":
                    cv.set(x0 + dx, y0 + dy, ch)


def griffon_head(cv, cx, cy, eye="open", mouth="smile", ear="normal", blush=False):
    # ears: small, set high on the corners, tips folding forward/outward
    tilt = {"normal": 0.55, "perk": 0.25, "flap": 0.95, "flat": 1.35}[ear]
    lift = {"normal": 0, "perk": -1, "flap": 0, "flat": 2}[ear]
    for side in (-1, 1):
        cv.ellipse(cx + side * 7.2, cy - 5.6 + lift, 2.0, 2.8, "d", angle=-side * tilt)
    # head: big and round
    cv.ellipse(cx, cy, 9.6, 8.0, "t")
    # light beard mask: rises up between the eyes (so the black nose reads) and hangs past the chin
    cv.ellipse(cx, cy + 4.6, 6.0, 4.4, "m", outline=False)
    cv.ellipse(cx, cy + 0.6, 2.2, 2.2, "m", outline=False)
    for x in range(int(cx - 5.5), int(cx + 6.5)):
        d = abs(x - cx)
        if d < 5:
            cv.set(x, cy + 8.6, "m")
        if d < 4 and int(x) % 2 == 0:
            cv.set(x, cy + 9.6, "m")
    # moustache flaring sideways past the cheeks
    for side in (-1, 1):
        cv.px([(cx + side * 6.5, cy + 4), (cx + side * 7.5, cy + 5), (cx + side * 7.5, cy + 6),
               (cx + side * 6.5, cy + 7)], "m")
    # eyes: huge, wide-set
    ey = int(round(cy - 2.5))
    left_x0, right_x0 = int(round(cx - 6.5)), int(round(cx + 2.5))
    griffon_eye(cv, left_x0, ey, eye)
    griffon_eye(cv, right_x0, ey, eye)
    # long bushy brows sweeping outward
    for side, x0 in ((-1, left_x0), (1, right_x0)):
        if eye == "sad":
            pts = [(x0 + (0 if side < 0 else 3), ey - 1), (x0 + 1.5, ey - 1.5), (x0 + (3 if side < 0 else 0), ey - 2)]
        else:
            pts = [(x0 + (3 if side < 0 else 0), ey - 1), (x0 + 1.5, ey - 2), (x0 + (0 if side < 0 else 3), ey - 2),
                   (x0 + (-1 if side < 0 else 4), ey - 1.5)]
        cv.px(pts, "m")
    # tiny upturned nose, high, right between the eyes
    ny = ey + 3
    cv.px([(cx - 1.5, ny), (cx - 0.5, ny), (cx + 0.5, ny), (cx + 1.5, ny), (cx - 1.5, ny + 1), (cx - 0.5, ny + 1),
           (cx + 0.5, ny + 1), (cx + 1.5, ny + 1), (cx - 0.5, ny + 2), (cx + 0.5, ny + 2)], "k")
    cv.set(cx - 0.5, ny, "w")
    if blush:
        cv.set(cx - 7.5, cy + 2, "h")
        cv.set(cx + 7.5, cy + 2, "h")
    # mouth inside the beard: underbite with two little teeth
    my = int(round(cy + 5.5))
    if mouth == "smile":
        cv.px([(cx - 2.5, my), (cx - 1.5, my + 1), (cx - 0.5, my + 1), (cx + 0.5, my + 1), (cx + 1.5, my + 1),
               (cx + 2.5, my)], "o")
        cv.px([(cx - 1.5, my), (cx + 1.5, my)], "w")
    elif mouth == "tongue":
        cv.px([(cx - 2.5, my), (cx - 1.5, my + 1), (cx - 0.5, my + 1), (cx + 0.5, my + 1), (cx + 1.5, my + 1),
               (cx + 2.5, my)], "o")
        cv.px([(cx - 1.5, my), (cx + 1.5, my)], "w")
        cv.px([(cx - 0.5, my + 2), (cx + 0.5, my + 2), (cx - 0.5, my + 3), (cx + 0.5, my + 3)], "p")
    elif mouth == "open":
        cv.px([(cx - 1.5, my), (cx - 0.5, my), (cx + 0.5, my), (cx + 1.5, my), (cx - 2.5, my + 1),
               (cx + 2.5, my + 1), (cx - 1.5, my + 2), (cx + 1.5, my + 2), (cx - 0.5, my + 3), (cx + 0.5, my + 3)], "o")
        cv.px([(cx - 1.5, my + 1), (cx - 0.5, my + 1), (cx + 0.5, my + 1), (cx + 1.5, my + 1),
               (cx - 0.5, my + 2), (cx + 0.5, my + 2)], "p")
    elif mouth == "frown":
        cv.px([(cx - 2.5, my + 1), (cx - 1.5, my), (cx - 0.5, my), (cx + 0.5, my), (cx + 1.5, my),
               (cx + 2.5, my + 1)], "o")


def griffon_sitting(cx=15.5, dy=0, eye="open", mouth="smile", ear="normal", tail_a=0.4,
                    paw="down", blush=False, bob=0):
    cv = Canvas()
    by = 24 + dy
    # short tail carried high
    cv.ellipse(cx + 6.2, by - 2.5, 1.3, 2.6, "t", angle=tail_a)
    # compact body
    cv.ellipse(cx, by, 6.0, 5.4, "t")
    cv.px([(cx - 2.5, by - 1), (cx + 2.5, by - 1), (cx - 1.5, by + 1), (cx + 1.5, by + 1)], "d")  # coat texture
    lp = {"down": (4.8, 4.8), "left": (4.0, 5.0), "right": (5.0, 4.0), "raised": (4.8, None)}[paw]
    for side, ly in ((-1, lp[0]), (1, lp[1])):
        if ly is not None:
            cv.ellipse(cx + side * 2.8, by + ly, 1.8, 1.3, "t")
            cv.set(cx + side * 2.8, by + ly + 0.6, "d")
    if paw == "raised":
        cv.ellipse(cx + 6.0, by - 2.0, 1.6, 1.6, "t")
    cy = 10.5 + dy + bob
    griffon_head(cv, cx, cy, eye=eye, mouth=mouth, ear=ear, blush=blush)
    # collar peeking out beside the beard
    y = int(round(cy + 8.5))
    for x in range(int(cx - 6), int(cx + 7)):
        if cv.get(x, y) == "t":
            cv.set(x, y, "r")
    return cv


def griffon_lying(z_phase=0, breathe=0):
    cv = Canvas()
    cv.ellipse(26, 25.5, 1.3, 2.4, "t", angle=0.9)
    cv.ellipse(20, 26 - breathe * 0.4, 8.6, 4.6 + breathe * 0.4, "t")
    cv.px([(18, 24), (22, 25), (25, 24)], "d")
    cv.ellipse(7, 29.6, 2.2, 1.3, "t")
    cv.ellipse(15, 29.6, 2.2, 1.3, "t")
    griffon_head(cv, 11.5, 20, eye="closed", mouth="smile", blush=True)
    zs(cv, z_phase)
    return cv


def griffon_frames():
    S = griffon_sitting
    f = {}
    f["idle"] = [griffon_lying(0, 0).rows(), griffon_lying(1, 1).rows(), griffon_lying(2, 0).rows()]
    f["stretch"] = [S(eye="closed").rows(), S(eye="closed", mouth="open", ear="perk").rows(), S().rows()]
    f["look"] = [S(cx=15.5 + dx, ear="perk").rows() for dx in (0, -1, -1, 0, 1, 1, 0)]
    w = []
    for i, (paw, bob, ear) in enumerate([("left", 0, "normal"), ("down", -1, "flap"),
                                         ("right", 0, "normal"), ("down", -1, "flap")]):
        cv = S(mouth="tongue", ear=ear, paw=paw, bob=bob, tail_a=0.1 if i % 2 else 0.7)
        speed_lines(cv, i % 2)
        w.append(cv.rows())
    f["working"] = w
    f["waiting"] = [S(eye="wide", mouth="open", ear="perk", paw="raised", tail_a=0.2).rows(),
                    S(dy=-1, eye="wide", ear="perk", paw="raised", tail_a=0.8).rows()]
    d = []
    for i, a in enumerate((0.0, 0.6, 1.0, 0.6)):
        cv = S(eye="happy", mouth="tongue", tail_a=a, blush=True)
        sparkles(cv, i)
        d.append(cv.rows())
    f["done"] = d
    fl = []
    for i in range(2):
        cv = S(dy=i, eye="sad", mouth="frown", ear="flat", tail_a=1.5)
        sweat(cv, 27, 4 + i)
        fl.append(cv.rows())
    f["failed"] = fl
    return f


# ---------- robot ----------

def robot(eye="open", light="g", arms="down", dy=0, look=0, screen_extra=None, slump=0):
    cv = Canvas()
    hy = 5 + dy + slump
    # antenna
    cv.px([(16, hy - 1), (16, hy - 2)], "g")
    cv.rect(15, hy - 4, 17, hy - 3, light, round_corners=False)
    # treads
    cv.rect(8, 28 + dy, 13, 30 + dy, "n", round_corners=True)
    cv.rect(18, 28 + dy, 23, 30 + dy, "n", round_corners=True)
    # body
    cv.rect(9, 19 + dy, 22, 28 + dy, "s", round_corners=True)
    cv.rect(12, 21 + dy, 19, 25 + dy, "g")
    cv.px([(14, 23 + dy), (15, 23 + dy), (16, 23 + dy), (17, 23 + dy)], light if light != "g" else "n")
    # arms
    if arms == "down":
        cv.rect(5, 20 + dy, 7, 26 + dy, "g", round_corners=True)
        cv.rect(24, 20 + dy, 26, 26 + dy, "g", round_corners=True)
    elif arms == "wave":
        cv.rect(5, 20 + dy, 7, 26 + dy, "g", round_corners=True)
        cv.rect(24, 12 + dy, 26, 19 + dy, "g", round_corners=True)
    elif arms == "up":
        cv.rect(5, 12 + dy, 7, 19 + dy, "g", round_corners=True)
        cv.rect(24, 12 + dy, 26, 19 + dy, "g", round_corners=True)
    elif arms == "left":
        cv.rect(5, 18 + dy, 7, 24 + dy, "g", round_corners=True)
        cv.rect(24, 21 + dy, 26, 27 + dy, "g", round_corners=True)
    elif arms == "right":
        cv.rect(5, 21 + dy, 7, 27 + dy, "g", round_corners=True)
        cv.rect(24, 18 + dy, 26, 24 + dy, "g", round_corners=True)
    # neck + head
    cv.rect(14, 17 + dy, 17, 18 + dy, "g", outline=False)
    cv.rect(7, hy, 24, hy + 12, "s", round_corners=True)
    cv.px([(6, hy + 5), (6, hy + 6), (6, hy + 7), (25, hy + 5), (25, hy + 6), (25, hy + 7)], "g")  # ear bolts
    cv.rect(9, hy + 2, 22, hy + 10, "n", outline=False)
    # face on the screen
    ey = hy + 4
    for side in (-1, 1):
        ex = 15.5 + side * 3.5 + look
        x0 = int(round(ex - 1))
        if eye == "open":
            cv.px([(x0, ey), (x0 + 1, ey), (x0, ey + 1), (x0 + 1, ey + 1), (x0, ey + 2), (x0 + 1, ey + 2)], "e")
            cv.set(x0, ey, "w")
        elif eye == "closed":
            cv.px([(x0 - 1, ey + 2), (x0, ey + 2), (x0 + 1, ey + 2), (x0 + 2, ey + 2)], "e")
        elif eye == "happy":
            cv.px([(x0 - 1, ey + 2), (x0, ey + 1), (x0 + 1, ey + 1), (x0 + 2, ey + 2)], "e")
        elif eye == "x":
            cv.px([(x0 - 1, ey), (x0 + 2, ey), (x0, ey + 1), (x0 + 1, ey + 1), (x0 - 1, ey + 2), (x0 + 2, ey + 2)], "R")
        elif eye == "wide":
            cv.px([(x0 - 1, ey - 1), (x0, ey - 1), (x0 + 1, ey - 1), (x0 + 2, ey - 1),
                   (x0 - 1, ey), (x0 + 2, ey), (x0 - 1, ey + 1), (x0 + 2, ey + 1),
                   (x0 - 1, ey + 2), (x0, ey + 2), (x0 + 1, ey + 2), (x0 + 2, ey + 2)], "e")
            cv.px([(x0, ey), (x0 + 1, ey + 1)], "w")
    if screen_extra == "smile":
        cv.px([(14, hy + 8), (15, hy + 9), (16, hy + 9), (17, hy + 8)], "e")
    elif screen_extra == "flat":
        cv.px([(14, hy + 9), (15, hy + 9), (16, hy + 9), (17, hy + 9)], "e")
    elif screen_extra == "o":
        cv.px([(15, hy + 8), (16, hy + 8), (15, hy + 9), (16, hy + 9)], "e")
    elif screen_extra == "frown":
        cv.px([(14, hy + 9), (15, hy + 8), (16, hy + 8), (17, hy + 9)], "R")
    elif isinstance(screen_extra, int):  # loading dots
        for i in range(3):
            cv.set(13 + i * 3, hy + 9, "e" if i == screen_extra else "g")
    return cv


def robot_frames():
    f = {}
    idle = []
    for i in range(3):
        cv = robot(eye="closed", light="g", screen_extra="flat", slump=1)
        zs(cv, i, spots=((22, 9), (25, 5), (28, 1)))
        idle.append(cv.rows())
    f["idle"] = idle
    f["stretch"] = [robot(eye="closed", arms="up", screen_extra="o").rows(),
                    robot(eye="open", arms="up", dy=-1, screen_extra="o").rows(),
                    robot(eye="open", screen_extra="smile").rows()]
    f["look"] = [robot(eye="open", look=dx, screen_extra="flat").rows() for dx in (0, -2, -2, 0, 2, 2, 0)]
    w = []
    for i, arms in enumerate(("left", "down", "right", "down")):
        cv = robot(eye="open", light="y" if i % 2 == 0 else "g", arms=arms, dy=-(i % 2), screen_extra=i % 3)
        speed_lines(cv, i % 2)
        w.append(cv.rows())
    f["working"] = w
    f["waiting"] = [robot(eye="wide", light="a", arms="wave", screen_extra="o").rows(),
                    robot(eye="wide", light="g", arms="wave", dy=-1, screen_extra="o").rows()]
    d = []
    for i in range(4):
        cv = robot(eye="happy", light="G", arms="up" if i % 2 == 0 else "down", dy=-(i % 2 == 0),
                   screen_extra="smile")
        sparkles(cv, i)
        d.append(cv.rows())
    f["done"] = d
    fl = []
    for i in range(2):
        cv = robot(eye="x", light="R" if i == 0 else "g", screen_extra="frown", slump=1)
        cv.px([(25, 2 + i), (26, 1 + i), (27, 2 + i), (26, 3 + i), (28, 0 + i)], "z")  # smoke puff
        fl.append(cv.rows())
    f["failed"] = fl
    return f


# ---------- output ----------

ORDER = ["idle", "stretch", "look", "working", "waiting", "done", "failed"]

CHARACTERS = [
    # (id, display name, palette, frames builder)
    # Gus the griffon (griffon_frames) is parked for now — add him back here to ship him.
    ("pixel-golden", "Sunny|Golden Dog", GOLDEN, lambda: animal(golden_head, "dog", belly=True)),
    ("pixel-cat", "Mochi|Cat", CAT, lambda: animal(cat_head, "cat", belly=True)),
    ("pixel-robot", "Bolt|Robot", ROBOT, robot_frames),
]


def swift_string(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def write_swift(built):
    out = ["// Generated by tools/gen_sprites.py — edit there, or tweak the grids below by hand.",
           "// One character per pixel; each pet has its own palette legend. '.' is transparent.",
           "",
           "struct PixelCharacter {",
           "    let id: String",
           "    let displayName: String",
           "    let species: String",
           "    let palette: [Character: (UInt8, UInt8, UInt8)]",
           "    let frames: [String: [[String]]]",
           "}",
           "",
           "enum PixelSprites {",
           "    static let characters: [PixelCharacter] = all",
           "",
           "    private static let all: [PixelCharacter] = ["]
    for cid, name, pal, frames in built:
        out.append("        PixelCharacter(")
        out.append(f'            id: "{cid}",')
        pet_name, species = name.split("|")
        out.append(f'            displayName: "{swift_string(pet_name)}",')
        out.append(f'            species: "{swift_string(species)}",')
        out.append("            palette: [")
        for k, (r, g, b) in pal.items():
            out.append(f'                "{k}": ({r}, {g}, {b}),')
        out.append("            ],")
        out.append("            frames: [")
        for state in ORDER:
            out.append(f'                "{state}": [')
            for rows in frames[state]:
                out.append("                    [")
                for r in rows:
                    out.append(f'                        "{r}",')
                out.append("                    ],")
            out.append("                ],")
        out.append("            ]")
        out.append("        ),")
    out.append("    ]")
    out.append("}")
    path = os.path.join(ROOT, "Sources", "RaicodePet", "PixelSprites.swift")
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


def write_preview(built, scale=5):
    from PIL import Image, ImageDraw
    cols = max(len(v) for _, _, _, fr in built for v in fr.values())
    pad, label_w = 6, 110
    rows_total = len(built) * len(ORDER)
    img = Image.new("RGB", (label_w + cols * (W * scale + pad) + pad,
                            rows_total * (H * scale + pad) + pad + len(built) * 20), (236, 238, 242))
    dr = ImageDraw.Draw(img)
    y0 = pad
    for cid, name, pal, frames in built:
        dr.text((8, y0), name.replace("|", " — "), fill=(0, 0, 0))
        y0 += 20
        for state in ORDER:
            dr.text((8, y0 + H * scale // 2 - 6), state, fill=(60, 60, 60))
            for c, rows in enumerate(frames[state]):
                x0 = label_w + c * (W * scale + pad)
                dr.rectangle([x0, y0, x0 + W * scale - 1, y0 + H * scale - 1], fill=(255, 255, 255))
                for y, row in enumerate(rows):
                    for x, ch in enumerate(row):
                        if ch in pal:
                            dr.rectangle([x0 + x * scale, y0 + y * scale, x0 + x * scale + scale - 1,
                                          y0 + y * scale + scale - 1], fill=pal[ch])
            y0 += H * scale + pad
    img.save(os.path.join(ROOT, "tools", "preview.png"))


def build():
    return [(cid, name, pal, fn()) for cid, name, pal, fn in CHARACTERS]


if __name__ == "__main__":
    b = build()
    for cid, _, pal, frames in b:
        for state, fr in frames.items():
            for rows in fr:
                assert len(rows) == H and all(len(r) == W for r in rows), (cid, state)
                missing = {ch for r in rows for ch in r} - set(pal) - {"."}
                assert not missing, (cid, state, missing)
    write_swift(b)
    write_preview(b)
    print("ok:", [(cid, {k: len(v) for k, v in fr.items()}) for cid, _, _, fr in b])
