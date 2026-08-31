#!/usr/bin/env python3
"""
gen_icons.py — render Resources/icon.svg into the PNG sizes iOS 6-9 expect.

iOS 6/7 (pre-asset-catalog) icons live as flat files in the app bundle,
declared in Info.plist via CFBundleIconFiles. Required sizes for
iPhone/iPad (non-Retina + Retina @2x):

  Icon.png            57x57    (iPhone)
  Icon@2x.png        114x114   (iPhone Retina)
  Icon-72.png         72x72    (iPad)
  Icon-72@2x.png     144x144   (iPad Retina)

The rendering is a dependency-free re-implementation of the SVG: a green
rounded square plus a bold white "E" drawn with Pillow's truetype/fallback
font. CI runs this same script (Pillow is installed there), so the icons
are reproducible without checking binaries into the repo.

Usage: python3 tools/gen_icons.py <output_dir>
"""

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.stderr.write("gen_icons: Pillow is required (pip install pillow)\n")
    sys.exit(1)

GREEN = (82, 181, 75, 255)     # #52B54B Emby green
WHITE = (255, 255, 255, 255)

# (filename, pixel size)
ICONS = [
    ("Icon.png", 57),
    ("Icon@2x.png", 114),
    ("Icon-72.png", 72),
    ("Icon-72@2x.png", 144),
    ("Icon-60@2x.png", 120),    # iOS 7+ spot if the app runs on newer devices
    ("Icon-76.png", 76),
    ("Icon-76@2x.png", 152),
]

FONT_CANDIDATES = [
    "C:/Windows/Fonts/arialbd.ttf",          # Windows CI/dev box
    "C:/Windows/Fonts/arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",  # Ubuntu CI
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",   # macOS (just in case)
]


def find_font():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    return None


def render(size):
    """Green square + big white bold E, supersampled for smooth edges."""
    ss = 4  # supersample factor
    big = size * ss
    img = Image.new("RGBA", (big, big), GREEN)
    draw = ImageDraw.Draw(img)

    fontpath = find_font()
    # Try to fill ~72% of the canvas height with the glyph.
    font = None
    if fontpath:
        try:
            font = ImageFont.truetype(fontpath, int(big * 0.82))
        except Exception:
            font = None
    if font is None:
        font = ImageFont.load_default()

    # Measure the glyph and center it.
    try:
        bbox = draw.textbbox((0, 0), "E", font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        x = (big - w) / 2 - bbox[0]
        y = (big - h) / 2 - bbox[1]
    except AttributeError:  # Pillow < 8 fallback
        w, h = draw.textsize("E", font=font)
        x = (big - w) / 2
        y = (big - h) / 2
    draw.text((x, y), "E", font=font, fill=WHITE)

    return img.resize((size, size), Image.LANCZOS)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(outdir, exist_ok=True)
    font_used = find_font()
    if font_used:
        print("gen_icons: using font %s" % font_used)
    else:
        print("gen_icons: no truetype font found; using bitmap fallback")
    for name, size in ICONS:
        path = os.path.join(outdir, name)
        render(size).save(path, "PNG")
        print("gen_icons: wrote %s (%dx%d)" % (path, size, size))


if __name__ == "__main__":
    main()
