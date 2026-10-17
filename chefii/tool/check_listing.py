"""Checks store listing copy in docs/store/LISTING.md against store limits."""
import re, sys

text = open('docs/store/LISTING.md', encoding='utf-8').read()

def section(title):
    m = re.search(r'^## ' + re.escape(title) + r'.*?\n(.*?)(?=^## |\Z)', text, re.S | re.M)
    return m.group(1) if m else ''

def table_values(body):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r'^\| (en|fr) \| (.+?) \|$', body, re.M)}

def bold_values(body):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r'^\*\*(en|fr)\s?:\*\*\s*(.+)$', body, re.M)}

def full(body, lang):
    m = re.search(r'^### ' + lang + r'\n(.*?)(?=^### |\Z)', body, re.S | re.M)
    return m.group(1).strip() if m else ''

checks = [
    ('App name', table_values(section('App name')), 30),
    ('Subtitle', table_values(section('App Store subtitle')), 30),
    ('Promotional text', bold_values(section('App Store promotional text')), 170),
    ('Keywords', bold_values(section('App Store keywords')), 100),
    ('Play short description', bold_values(section('Google Play short description')), 80),
]
body = section('Full description')
checks.append(('Full description', {'en': full(body, 'en'), 'fr': full(body, 'fr')}, 4000))

ok = True
for name, values, limit in checks:
    for lang in ('en', 'fr'):
        v = values.get(lang, '')
        n = len(v)
        status = 'OK ' if 0 < n <= limit else 'BAD'
        ok &= status == 'OK '
        print(f'{status} {name} [{lang}] {n}/{limit}')
sys.exit(0 if ok else 1)
