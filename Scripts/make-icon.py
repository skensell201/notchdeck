#!/usr/bin/env python3
"""Draws Resources/AppIcon.icns from scratch.

The icon is generated rather than checked in as a binary blob nobody can edit:
the shape is a few numbers, and this way a tweak is a diff. Run it after
changing anything here, then commit the regenerated .icns alongside.
"""
import pathlib
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
CANVAS = 1024
# The system's squircle mask clips the corners of a full-bleed icon; the glyph
# stays inside this fraction of the canvas so nothing important is lost to it.
SAFE_AREA = 0.86


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return grad.resize((size, size), Image.BILINEAR)


def render(scale=4):
    """Renders at `scale`x and downsamples, so every curve lands antialiased.

    The artwork is full-bleed on purpose: macOS 26 masks an app icon into its
    own squircle and casts its own shadow. Drawing a plate here too would put a
    second, smaller tile inside the system's one.
    """
    size = CANVAS * scale
    img = vertical_gradient(size, (58, 58, 62), (18, 18, 21)).convert("RGBA")

    # Everything sits inside a safe area, because the system's mask eats the
    # corners and its Liquid Glass treatment crops a little further still.
    safe = round(size * SAFE_AREA)
    origin = (size - safe) // 2
    d = ImageDraw.Draw(img)

    # The glyph: the notch itself. Flat where it meets the top of the screen,
    # rounded where it juts down into it — the one silhouette this app is
    # named after.
    notch_w = round(safe * 0.80)
    notch_h = round(safe * 0.300)
    card_h = round(safe * 0.280)
    spacer = round(safe * 0.130)
    # Centre the group as a whole rather than pad from the top, so a change to
    # any one band cannot quietly push the glyph off-centre.
    notch_x = (size - notch_w) // 2
    notch_y = origin + (safe - (notch_h + spacer + card_h)) // 2

    radius = notch_h // 2
    # Overdraw the top by `radius` and repaint the gradient over that strip: a
    # pill whose upper corners are square, rather than a lozenge.
    d.rounded_rectangle((notch_x, notch_y - radius, notch_x + notch_w, notch_y + notch_h),
                        radius=radius, fill=(255, 255, 255, 255))
    strip = (notch_x, notch_y - radius, notch_x + notch_w, notch_y)
    img.paste(vertical_gradient(size, (58, 58, 62), (18, 18, 21)).crop(strip), strip[:2])

    # The deck: three cards below the notch, the modules it holds.
    card_y = notch_y + notch_h + spacer
    gap = round(safe * 0.058)
    card_w = (notch_w - 2 * gap) // 3
    card_r = round(card_w * 0.30)
    for i, tint in enumerate([(255, 159, 10, 255), (255, 55, 95, 255), (10, 132, 255, 255)]):
        x = notch_x + i * (card_w + gap)
        d.rounded_rectangle((x, card_y, x + card_w, card_y + card_h), radius=card_r, fill=tint)

    return img.resize((CANVAS, CANVAS), Image.LANCZOS)


def main():
    master = render()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for pt in (16, 32, 128, 256, 512):
            for factor, suffix in ((1, ""), (2, "@2x")):
                px = pt * factor
                master.resize((px, px), Image.LANCZOS).save(
                    iconset / f"icon_{pt}x{pt}{suffix}.png")
        out = ROOT / "Resources" / "AppIcon.icns"
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
        print(out)


if __name__ == "__main__":
    if shutil.which("iconutil") is None:
        raise SystemExit("iconutil not found — this script needs macOS.")
    main()
