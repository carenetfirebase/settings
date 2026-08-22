"""13D / 13G parsing and Item 4 classification.

**13D and 13G are not the same filing and conflating them is a correctness
bug** (SPEC §8). A 13D declares active intent — the filer means to influence
control. A 13G declares the opposite: a passive position, typically an index
fund crossing 5%. Scoring an index fund's passive stake as activist pressure
would put a mechanical, information-free event at the top of the ranking.

The distinction is never inferred from content. It comes from the form type,
which the SEC assigns.

Item 4 ("Purpose of Transaction") is classified by deterministic keyword
matching first (SPEC §8). A local LLM may be layered on top later and its
output is labelled interpretation, never fact.
"""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation

from imt.adapters.records import ActivistRecord, FilingRef
from imt.core.logging import get_logger

log = get_logger(__name__)

SOURCE_ID = "sec_edgar"

ACTIVIST_FORMS = frozenset({"SC 13D", "SC 13D/A"})
PASSIVE_FORMS = frozenset({"SC 13G", "SC 13G/A"})

#: SPEC §8's Item 4 categories. Ordered most-specific first, because
#: "merger" appears inside discussions of "strategic alternatives" and the
#: more specific reading is the more useful one.
ITEM4_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "board_representation",
        re.compile(
            r"board (?:of directors )?(?:seat|representation|nominee)|nominate .{0,30}director",
            re.I,
        ),
    ),
    (
        "management_change",
        re.compile(r"replace .{0,30}(?:management|chief executive|ceo)|management change", re.I),
    ),
    (
        "strategic_alternatives",
        re.compile(
            r"strategic alternatives|review of alternatives|explore .{0,20}alternatives", re.I
        ),
    ),
    (
        "sale_of_company",
        re.compile(r"sale of the (?:company|issuer)|sell the (?:company|issuer)", re.I),
    ),
    ("merger", re.compile(r"\bmerger\b|business combination", re.I)),
    ("restructuring", re.compile(r"restructur|reorganiz", re.I)),
    (
        "capital_allocation",
        re.compile(r"capital allocation|dividend policy|return of capital", re.I),
    ),
    ("share_repurchase", re.compile(r"repurchase|buy ?back", re.I)),
)

_PCT = re.compile(
    r"(?:percent(?:age)? of class|aggregate(?:ly)? .{0,20}percent)"
    r"[^0-9]{0,40}([0-9]{1,3}(?:\.[0-9]+)?)\s*%",
    re.I,
)
_PCT_FALLBACK = re.compile(r"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*of .{0,20}class", re.I)
_SHARES = re.compile(r"aggregate amount beneficially owned[^0-9]{0,60}([0-9][0-9,]{3,})", re.I)
_TAGS = re.compile(r"<[^>]+>")


def is_activist_form(form_type: str) -> bool:
    """13D is activist, 13G is passive. Never inferred from content.

    Raises on anything else rather than guessing — a 13F or an SC 14D9 reaching
    this function is a routing bug, and defaulting it to "passive" would hide
    that.
    """
    normalized = form_type.strip().upper()
    if normalized in ACTIVIST_FORMS:
        return True
    if normalized in PASSIVE_FORMS:
        return False
    raise ValueError(
        f"{form_type!r} is neither a 13D nor a 13G. The activist/passive "
        f"distinction comes from the form type and is never guessed."
    )


def strip_markup(html: str) -> str:
    text = _TAGS.sub(" ", html)
    return re.sub(r"\s+", " ", text).strip()


def classify_item4(text: str) -> tuple[str, ...]:
    """Deterministic keyword classification of Item 4.

    Returns every category that matched, in the declared order. An empty tuple
    means nothing matched, which is a real answer — the UI shows "unclassified"
    rather than picking the nearest bucket.
    """
    plain = strip_markup(text)
    return tuple(name for name, pattern in ITEM4_PATTERNS if pattern.search(plain))


def _decimal_or_none(raw: str | None) -> Decimal | None:
    if raw is None:
        return None
    try:
        return Decimal(raw.replace(",", ""))
    except (InvalidOperation, ValueError):
        return None


def parse_ownership(
    payload: bytes, *, ref: FilingRef, filer_name: str | None = None
) -> ActivistRecord:
    """Parse a 13D/13G document.

    These are prose filings, not XML, so extraction is regex over stripped
    text and is inherently lossy. Anything not confidently found is None with
    the field left empty rather than a plausible-looking default — a fabricated
    ownership percentage would feed straight into a score.
    """
    text = strip_markup(payload.decode("utf-8", errors="replace"))
    is_activist = is_activist_form(ref.form_type)

    match = _PCT.search(text) or _PCT_FALLBACK.search(text)
    pct = _decimal_or_none(match.group(1)) if match else None
    if pct is not None and not (Decimal(0) <= pct <= Decimal(100)):
        log.info("ownership.implausible_pct", accession=ref.accession, pct=str(pct))
        pct = None

    shares_match = _SHARES.search(text)
    shares = _decimal_or_none(shares_match.group(1)) if shares_match else None

    # Item 4 exists only on a 13D. A 13G has no purpose section, because its
    # whole point is the absence of one.
    categories = classify_item4(text) if is_activist else ()

    return ActivistRecord(
        cik=ref.cik,
        accession=ref.accession,
        filer_name=filer_name or ref.company_name or "UNKNOWN",
        is_activist=is_activist,
        pct_of_class=pct,
        shares=shares,
        item4_categories=categories,
    )
