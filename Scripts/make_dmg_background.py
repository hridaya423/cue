"""Draws the DMG window background (Resources/dmg/background.tiff, 1x + 2x) from the wordmark's own stripe data.
Run: uv run --with pillow Scripts/make_dmg_background.py"""
import re
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Resources/dmg"
W, H = 660, 400
ICON_Y, LEFT_X, RIGHT_X = 200, 170, 490
COBALT = (0x14, 0x63, 0xEC)

src = (ROOT / "Sources/CueKit/Views/Wordmark.swift").read_text()
ASPECT = float(re.search(r"aspect: CGFloat = ([\d.]+)", src).group(1))
RUNS = [(int(r), float(a), float(b)) for r, a, b in re.findall(r"row: (\d+), from: ([\d.]+), to: ([\d.]+)", src)]


def draw(scale: int) -> Image.Image:
    s = scale * 4  # supersample, then downscale for clean capsule edges
    w, h = W * s, H * s
    img = Image.new("RGB", (w, h))
    top, bottom = (255, 255, 255), (236, 242, 255)
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([w * 0.18, h * 0.30, w * 0.82, h * 0.95], fill=46)
    glow = glow.filter(ImageFilter.GaussianBlur(70 * s))
    img = Image.composite(Image.new("RGB", (w, h), (196, 214, 255)), img, glow)
    d = ImageDraw.Draw(img, "RGBA")

    mark_h = 30 * s
    mark_w = mark_h * ASPECT
    x0, y0 = (w - mark_w) / 2, 46 * s
    pitch = mark_h / 9
    for row, a, b in RUNS:
        ry = y0 + row * pitch + pitch * 0.19
        d.rounded_rectangle([x0 + a * mark_w, ry, x0 + b * mark_w, ry + pitch * 0.62],
                            radius=pitch * 0.31, fill=COBALT + (255,))

    ay, ax0, ax1 = ICON_Y * s, (LEFT_X + 78) * s, (RIGHT_X - 78) * s
    stroke = round(2.5 * s)
    arrow = COBALT + (120,)
    d.line([(ax0, ay), (ax1 - 2 * s, ay)], fill=arrow, width=stroke)
    head = 9 * s
    d.line([(ax1 - head, ay - head), (ax1, ay), (ax1 - head, ay + head)], fill=arrow, width=stroke, joint="curve")

    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 13 * s)
    text = "Drag Cue into Applications"
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, 330 * s), text, font=font, fill=(96, 104, 120, 255))
    return img.resize((W * scale, H * scale), Image.LANCZOS)


OUT.mkdir(parents=True, exist_ok=True)
draw(1).save(OUT / "background.png")
draw(2).save(OUT / "background@2x.png")
subprocess.run(["tiffutil", "-cathidpicheck", OUT / "background.png", OUT / "background@2x.png",
                "-out", OUT / "background.tiff"], check=True, capture_output=True)
(OUT / "background.png").unlink()
(OUT / "background@2x.png").unlink()
print(OUT / "background.tiff")
