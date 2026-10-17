"""Generates Chefii's brand assets from the bundled Cormorant Garamond font.

  python3 tool/make_icon.py

Writes assets/brand/: icon.png (1024, opaque, iOS), icon_foreground.png
(Android adaptive foreground, transparent), splash.png (launch logo).
Rendered at 4x and downsampled for smooth edges.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FOREST = (52, 68, 57)
CHAMPAGNE = (201, 175, 133)
SAGE = (176, 194, 152)
FONT = 'assets/fonts/CormorantGaramond-Variable.ttf'
OUT = 1024
SS = 4
S = OUT * SS


def mark(scale):
    """The 'c' + sprig, centred, occupying `scale` of the canvas height."""
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 1000)
    font.set_variation_by_name('SemiBold')
    probe = d.textbbox((0, 0), 'c', font=font)
    glyph_h = probe[3] - probe[1]
    # The whole mark (glyph + sprig above it) is ~1.55x the glyph height.
    target_h = S * scale / 1.55
    font = ImageFont.truetype(FONT, int(1000 * target_h / glyph_h))
    font.set_variation_by_name('SemiBold')
    bb = d.textbbox((0, 0), 'c', font=font)
    gw, gh = bb[2] - bb[0], bb[3] - bb[1]
    sprig_h = gh * 0.55
    total_h = gh + sprig_h
    left = (S - gw) / 2
    top = (S - total_h) / 2 + sprig_h
    d.text((left - bb[0], top - bb[1]), 'c', font=font, fill=CHAMPAGNE)

    # Sprig rises from the c's upper terminal.
    base = (left + gw * 0.78, top + gh * 0.04)
    tip = (base[0] + gh * 0.12, base[1] - sprig_h * 0.95)
    width = max(4, int(gh * 0.035))
    d.line([base, tip], fill=SAGE, width=width)
    for t, side in [(0.30, -1), (0.55, 1), (0.80, -1)]:
        px = base[0] + (tip[0] - base[0]) * t
        py = base[1] + (tip[1] - base[1]) * t
        lw, lh = gh * 0.22, gh * 0.09
        leaf = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(leaf).ellipse([px - lw, py - lh / 2, px, py + lh / 2] if side < 0 else [px, py - lh / 2, px + lw, py + lh / 2], fill=SAGE)
        leaf = leaf.rotate(-30 * side, center=(px, py), resample=Image.BICUBIC)
        img.alpha_composite(leaf)
    r = width * 0.9
    d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=SAGE)
    return img


def background():
    bg = Image.new('RGB', (S, S), FOREST)
    glow = Image.new('L', (S, S), 0)
    ImageDraw.Draw(glow).ellipse([-S * 0.25, -S * 0.4, S * 1.05, S * 0.8], fill=34)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.16))
    return Image.composite(Image.new('RGB', (S, S), (92, 114, 98)), bg, glow).convert('RGBA')


def save(img, path, opaque=False):
    out = img.resize((OUT, OUT), Image.LANCZOS)
    (out.convert('RGB') if opaque else out).save(path, optimize=True)


icon = background()
icon.alpha_composite(mark(0.62))
save(icon, 'assets/brand/icon.png', opaque=True)
save(mark(0.42), 'assets/brand/icon_foreground.png')  # within the adaptive-icon safe zone
save(mark(0.40), 'assets/brand/splash.png')
print('ok')
