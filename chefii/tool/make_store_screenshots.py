"""Builds framed store screenshots from raw app captures.

    python3 tool/make_store_screenshots.py <raw_dir_en> <raw_dir_fr>

Raw captures are 1320x2868 PNGs of the screenshot build
(--dart-define=CHEFII_SCREENSHOTS=true), named as in CAPTIONS below. Output:
store/screenshots/ios/{en,fr}/ (1320x2868, App Store 6.9" iPhone),
store/screenshots/android/{en,fr}/ (1080x1920, Google Play phone) and
store/feature_graphic_{en,fr}.png (1024x500, Google Play).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERIF = os.path.join(ROOT, 'assets/fonts/CormorantGaramond-Variable.ttf')
SANS = os.path.join(ROOT, 'assets/fonts/Inter-Variable.ttf')

PORCELAIN = (247, 244, 238)
FOREST = (52, 68, 57)
INK = (37, 41, 34)
GOLD = (122, 98, 64)

CAPTIONS = {
    'en': [
        ('1-today', 'Your kitchen, beautifully taken care of.'),
        ('2-receipt', 'Scan a receipt. Your kitchen fills itself in.'),
        ('3-kitchen', 'Know what you have, and what to use soon.'),
        ('4-recipe', 'Cook from what you already have.'),
        ('5-cooking', 'Calm, step-by-step cooking.'),
        ('7-dietary', "Recipes screened for your household's allergies."),
    ],
    'fr': [
        ('1-today', 'Votre cuisine, entre de bonnes mains.'),
        ('2-receipt', 'Numérisez un reçu, votre cuisine se remplit.'),
        ('3-kitchen', 'Sachez ce que vous avez et quoi utiliser bientôt.'),
        ('4-recipe', 'Cuisinez avec ce que vous avez déjà.'),
        ('5-cooking', 'Cuisinez sereinement, étape par étape.'),
        ('7-dietary', 'Des recettes vérifiées selon les allergies de votre foyer.'),
    ],
}

EYEBROW = {'en': 'CHEFII', 'fr': 'CHEFII'}
FEATURE = {
    'en': ('Your kitchen,', 'beautifully taken care of.'),
    'fr': ('Votre cuisine,', 'entre de bonnes mains.'),
}


def font(path, size, weight):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def wrap(draw, text, f, max_width):
    words, lines, line = text.split(), [], ''
    for w in words:
        trial = f'{line} {w}'.strip()
        if draw.textlength(trial, font=f) <= max_width:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def rounded(im, radius):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius, fill=255)
    out = Image.new('RGBA', im.size)
    out.paste(im, (0, 0), mask)
    return out


def frame(raw_path, caption, size):
    w, h = size
    s = w / 1320
    canvas = Image.new('RGB', size, PORCELAIN)
    draw = ImageDraw.Draw(canvas)
    eyebrow = font(SANS, int(30 * s), 600)
    head = font(SERIF, int(104 * s), 500)
    margin = int(110 * s)
    y = int(150 * s)
    draw.text((w / 2, y), 'C H E F I I', font=eyebrow, fill=GOLD, anchor='mm')
    y += int(70 * s)
    for line in wrap(draw, caption, head, w - 2 * margin):
        draw.text((w / 2, y), line, font=head, fill=INK, anchor='ma')
        y += int(118 * s)
    # Phone screen: scaled to fit the remaining space, bleeding off the bottom.
    shot = Image.open(raw_path).convert('RGB')
    top = y + int(50 * s)
    target_w = int(w * 0.80)
    scale = target_w / shot.width
    shot = shot.resize((target_w, int(shot.height * scale)), Image.LANCZOS)
    shot = rounded(shot, int(64 * s))
    x = (w - target_w) // 2
    shadow = Image.new('RGBA', (target_w + 120, shot.height + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([60, 60, target_w + 60, shot.height + 60], int(64 * s), fill=(37, 41, 34, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(28 * s)))
    canvas.paste(shadow, (x - 60, top - 40), shadow)
    canvas.paste(shot, (x, top), shot)
    return canvas


def feature_graphic(lang, raw_dir):
    w, h = 1024, 500
    canvas = Image.new('RGB', (w, h), FOREST)
    draw = ImageDraw.Draw(canvas)
    tw = 250
    text_w = w - tw - 64 - 64 - 48
    head = font(SERIF, 60, 500)
    eyebrow = font(SANS, 20, 600)
    lines = wrap(draw, ' '.join(FEATURE[lang]), head, text_w)
    y = (h - len(lines) * 70) // 2 + 10
    draw.text((64, y - 50), 'C H E F I I', font=eyebrow, fill=(214, 221, 198))
    for line in lines:
        draw.text((64, y), line, font=head, fill=PORCELAIN)
        y += 70
    shot = Image.open(os.path.join(raw_dir, '1-today.png')).convert('RGB')
    shot = shot.resize((tw, int(shot.height * tw / shot.width)), Image.LANCZOS)
    shot = rounded(shot.crop((0, 0, tw, 470)), 26)
    canvas.paste(shot, (w - tw - 64, 50), shot)
    return canvas


def main(raw_en, raw_fr):
    out = os.path.join(ROOT, 'store')
    for lang, raw in (('en', raw_en), ('fr', raw_fr)):
        for platform, size in (('ios', (1320, 2868)), ('android', (1080, 1920))):
            d = os.path.join(out, 'screenshots', platform, lang)
            os.makedirs(d, exist_ok=True)
            for i, (name, caption) in enumerate(CAPTIONS[lang], start=1):
                img = frame(os.path.join(raw, f'{name}.png'), caption, size)
                img.save(os.path.join(d, f'{i:02d}-{name.split("-", 1)[1]}.jpg'), quality=90, optimize=True)
        feature_graphic(lang, raw).save(os.path.join(out, f'feature_graphic_{lang}.png'), optimize=True)
    icon = Image.open(os.path.join(ROOT, 'assets/brand/icon.png')).convert('RGB').resize((512, 512), Image.LANCZOS)
    icon.save(os.path.join(out, 'play_icon_512.png'), optimize=True)
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
