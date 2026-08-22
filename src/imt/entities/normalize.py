"""Company-name normalization. One function, used identically by every source.

If two sources normalize names differently, they will fail to join on names
that are in fact the same company — and worse, occasionally join on names that
are not. Both failures are silent. So this lives in one place and every
resolver imports it rather than writing "just a quick strip" locally.

**Suffix stripping is positional.** ``THE`` is only stripped as a leading
token; every other suffix is only stripped as a trailing token. Unanchored
stripping is a real defect, not a hypothetical one:

    GROUP 1 AUTOMOTIVE  -> unanchored: "1 AUTOMOTIVE"    (wrong)
                        -> anchored:   "GROUP 1 AUTOMOTIVE" (correct)
    COCA COLA CO        -> anchored:   "COCA COLA"
"""

from __future__ import annotations

import re

# Stripped repeatedly from the END, longest first so "HOLDING COMPANY" goes
# before "COMPANY".
TRAILING_SUFFIXES: tuple[str, ...] = (
    "HOLDING COMPANY",
    "HOLDINGS",
    "HOLDING",
    "INCORPORATED",
    "CORPORATION",
    "COMPANY",
    "LIMITED",
    "GROUP",
    "TRUST",
    "CORP",
    "INC",
    "PLC",
    "LLC",
    "LTD",
    "LP",
    "CO",
    "SA",
    "NV",
    "AG",
)

LEADING_TOKENS: tuple[str, ...] = ("THE",)

_PUNCT = re.compile(r"[^\w\s]", flags=re.UNICODE)
_WHITESPACE = re.compile(r"\s+")


def normalize_name(raw: str) -> str:
    """Uppercase, strip punctuation, strip positional affixes, collapse space.

    >>> normalize_name("THE ACME HOLDINGS CORP.")
    'ACME'
    >>> normalize_name("Group 1 Automotive, Inc.")
    'GROUP 1 AUTOMOTIVE'
    >>> normalize_name("Coca-Cola Co")
    'COCA COLA'
    """
    if raw is None:
        return ""
    text = _PUNCT.sub(" ", raw.upper())
    text = _WHITESPACE.sub(" ", text).strip()
    if not text:
        return ""

    tokens = text.split(" ")

    # Leading: only ever the article, and only if something survives it.
    while len(tokens) > 1 and tokens[0] in LEADING_TOKENS:
        tokens = tokens[1:]

    # Trailing: repeat, because "ACME HOLDINGS CORP" carries two.
    changed = True
    while changed and len(tokens) > 1:
        changed = False
        for suffix in TRAILING_SUFFIXES:
            parts = suffix.split(" ")
            n = len(parts)
            if len(tokens) > n and tokens[-n:] == parts:
                tokens = tokens[:-n]
                changed = True
                break

    return " ".join(tokens)


def name_tokens(raw: str) -> frozenset[str]:
    """Normalized name as a token set, for token-set similarity scoring."""
    normalized = normalize_name(raw)
    return frozenset(normalized.split(" ")) if normalized else frozenset()
