"""Draws EsyType's app icon and tray icons (Pillow, already installed; run by hand, output checked in).

  python -I scripts/make-icons.py preview OUT.png        three candidates side by side, dark and light backgrounds
  python -I scripts/make-icons.py write A|B|C            writes src-tauri/icons for the chosen candidate
  python -I scripts/make-icons.py sidebar OUT.bmp        the installer's welcome/finish panel (black, the waveform)

Every size is drawn for its own size (not shrunk from 1024): 16 and 24 px get five thick bars snapped to whole
pixels so they stay sharp.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

SIZES = [256, 64, 48, 32, 24, 16]
BLUE, WHITE, AMBER = (0x27, 0x66, 0x9A), (255, 255, 255), (0xDF, 0xA1, 0x64)  # the recording pill's colours
RED = (0xEF, 0x44, 0x44)
SS = 8  # supersampling


def bars(variant, size):
    """(x, width, height, opacity) per bar, in target pixels, centred on the icon."""
    if size <= 24:  # five thick bars on whole pixels
        w = 2 if size <= 16 else 3
        pitch = 3 if size <= 16 else 4
        hs = [0.30, 0.50, 0.66, 0.50, 0.30]
        x0 = (size - (4 * pitch + w)) // 2
        return [(x0 + i * pitch, w, max(w, round(h * size)), 1.0) for i, h in enumerate(hs)]
    k = size / 1024
    if variant in ("A", "C") or size <= 48:  # today's nine bars, measured from icon-source.png
        hs = [208, 288, 424, 570, 636, 570, 424, 288, 208]
        return [((512 - 27 + (i - 4) * 88) * k, 54 * k, h * k, 1.0) for i, h in enumerate(hs)]
    # B (64 px and up; thin bars blur at 48 and below): fifteen thin bars under a smooth envelope, fading towards the edges like the favicon's fluted glass
    out = []
    for i in range(15):
        t = (i - 7) / 7
        env = math.cos(t * math.pi / 2)
        out.append(((512 - 15 + (i - 7) * 52) * k, 30 * k, (180 + 480 * env) * k, 0.35 + 0.65 * env))
    return out


def colour_at(y, top, bottom, variant):
    """Gradient along the bar field: amber at the top, white at 55% down, blue at the bottom (as the pill, 'to top')."""
    if variant == "C":
        return WHITE
    t = min(1, max(0, (y - top) / max(1, bottom - top)))
    a, b, u = (AMBER, WHITE, t / 0.55) if t < 0.55 else (WHITE, BLUE, (t - 0.55) / 0.45)
    return tuple(round(a[c] + (b[c] - a[c]) * u) for c in range(3))


def icon(variant, size, dot=False):
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=round(S * 0.22), fill=(0, 0, 0, 255))
    spec = bars(variant, size)
    top = min((size - h) / 2 for _, _, h, _ in spec) * SS
    bottom = max((size + h) / 2 for _, _, h, _ in spec) * SS
    grad = Image.new("RGBA", (1, S))
    for y in range(S):
        grad.putpixel((0, y), colour_at(y, top, bottom, variant) + (255,))
    grad = grad.resize((S, S))
    for x, w, h, op in spec:
        m = Image.new("L", (S, S), 0)
        y = (size - h) / 2
        if size <= 24:
            y = round(y)
        ImageDraw.Draw(m).rounded_rectangle([x * SS, y * SS, (x + w) * SS - 1, (y + h) * SS - 1], radius=w * SS / 2, fill=round(255 * op))
        img.paste(grad, (0, 0), m)
    if dot:  # recording: a red dot with a black ring, bottom right
        r, cx = S * 0.15, S * 0.79
        d.ellipse([cx - r - S * 0.045, cx - r - S * 0.045, cx + r + S * 0.045, cx + r + S * 0.045], fill=(0, 0, 0, 255))
        d.ellipse([cx - r, cx - r, cx + r, cx + r], fill=RED + (255,))
    return img.resize((size, size), Image.LANCZOS)


def preview(out):
    rows = []
    for v in "ABC":
        for bg in ((32, 32, 32), (243, 243, 243)):
            row = Image.new("RGB", (1180, 280), bg)
            x = 16
            for s in SIZES:
                im = icon(v, s)
                row.paste(im, (x, 12), im)
                x += s + 16
            for s in (32, 24, 16):  # small sizes enlarged 4x, pixel for pixel
                im = icon(v, s).resize((s * 4, s * 4), Image.NEAREST)
                row.paste(im, (x, 12), im)
                x += s * 4 + 16
            tray = icon(v, 32, dot=True)
            row.paste(tray, (x, 12), tray)
            tray4 = tray.resize((128, 128), Image.NEAREST)
            row.paste(tray4, (x + 48, 12), tray4)
            ImageDraw.Draw(row).text((16, 256), f"{v}   256 64 48 32 24 16 | 32 24 16 at 4x | tray while recording", fill=(128, 128, 128))
            rows.append(row)
    sheet = Image.new("RGB", (1180, 280 * len(rows)))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, 280 * i))
    sheet.save(out)


def write(v):
    d = os.path.join(os.path.dirname(__file__), "..", "src-tauri", "icons")
    imgs = {s: icon(v, s) for s in SIZES}
    imgs[256].save(os.path.join(d, "icon.ico"), sizes=[(s, s) for s in SIZES], append_images=[imgs[s] for s in SIZES[1:]])
    imgs[32].save(os.path.join(d, "32x32.png"))
    icon(v, 128).save(os.path.join(d, "128x128.png"))
    icon(v, 32, dot=True).save(os.path.join(d, "tray-recording.png"))
    # self-check: every ICO frame is the one drawn for its size
    ico = Image.open(os.path.join(d, "icon.ico"))
    for s in SIZES:
        ico.size = (s, s)
        assert ico.convert("RGBA").tobytes() == imgs[s].tobytes(), f"ICO frame {s} differs"
    print("wrote", v, "to", os.path.abspath(d))


def sidebar(out):
    """NSIS welcome/finish panel: 164x314 at 100%, drawn at 2x (NSIS scales it to the page): black, candidate A's
    bars in the pill's colours, a little above the middle."""
    W, H = 328, 628
    img = Image.new("RGB", (W, H), (0, 0, 0))
    mark = icon("A", 256).crop((24, 24, 232, 232))   # the bars without the rounded square's edge
    img.paste(mark, ((W - mark.width) // 2, H // 2 - mark.height // 2 - 40), mark)
    img.save(out)


if __name__ == "__main__":
    {"preview": lambda: preview(sys.argv[2]), "write": lambda: write(sys.argv[2]), "sidebar": lambda: sidebar(sys.argv[2])}[sys.argv[1]]()
