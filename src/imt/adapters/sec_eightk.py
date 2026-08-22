"""8-K item classification.

The SEC assigns item numbers, so the primary classification is deterministic
lookup rather than interpretation — item 5.02 *is* a director or officer
change, and no keyword pass can do better than the taxonomy itself.

Content keywords are a second pass, used only to add detail within an item and
to catch filings whose item list is missing from the index. Anything unplaced
stays ``unclassified``: Phase 2 criterion 5 asks for ≥80% of filings to carry
at least one classified item, and the honest way to fall short of that is to
report it, not to widen a bucket until everything fits.
"""

from __future__ import annotations

import re

from imt.core.logging import get_logger

log = get_logger(__name__)

#: The SEC's own taxonomy. Source of truth for classification.
ITEM_CATEGORIES: dict[str, str] = {
    "1.01": "material_agreement",
    "1.02": "agreement_termination",
    "1.03": "bankruptcy",
    "1.04": "mine_safety",
    "1.05": "cybersecurity_incident",
    "2.01": "acquisition_or_disposition",
    "2.02": "earnings",
    "2.03": "debt_obligation",
    "2.04": "debt_acceleration",
    "2.05": "restructuring_costs",
    "2.06": "impairment",
    "3.01": "listing_or_compliance",
    "3.02": "share_issuance",
    "3.03": "security_holder_rights",
    "4.01": "auditor_change",
    "4.02": "non_reliance_restatement",
    "5.01": "control_change",
    "5.02": "executive_change",
    "5.03": "charter_amendment",
    "5.07": "shareholder_vote",
    "7.01": "regulation_fd",
    "8.01": "other_events",
    "9.01": "exhibits",
}

#: Items that are administrative rather than informative. Present so that
#: "has a classified item" does not overstate how much a filing tells you: a
#: filing whose only item is 9.01 (exhibits) is not a catalyst.
LOW_SIGNAL_ITEMS = frozenset({"9.01", "7.01", "8.01"})

CONTENT_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("acquisition_or_disposition", re.compile(r"\bacquisit|\bacquire[sd]?\b|divest", re.I)),
    ("merger", re.compile(r"\bmerger\b|business combination", re.I)),
    (
        "government_contract",
        re.compile(r"\b(?:contract|task order) award|awarded a contract", re.I),
    ),
    ("financing", re.compile(r"\boffering\b|private placement|credit facility", re.I)),
    (
        "executive_change",
        re.compile(r"\bresign|\bappointed\b|\bstepping down\b|\bdeparture\b", re.I),
    ),
    ("guidance", re.compile(r"\bguidance\b|\boutlook\b|\bforecast\b", re.I)),
    ("restructuring", re.compile(r"restructur|workforce reduction|\blayoff", re.I)),
)

_ITEM_IN_TEXT = re.compile(r"item\s+(\d\.\d{2})", re.I)
_TAGS = re.compile(r"<[^>]+>")


def normalize_item(raw: str) -> str | None:
    """Index item strings arrive as '5.02', 'Item 5.02', or '5.02,5.07'."""
    match = re.search(r"(\d\.\d{2})", raw)
    return match.group(1) if match else None


def classify_items(items: list[str]) -> tuple[str, ...]:
    """Map SEC item numbers to categories. Unknown numbers are dropped."""
    out: list[str] = []
    for raw in items:
        for part in re.split(r"[,\s]+", raw):
            number = normalize_item(part)
            if number is None:
                continue
            category = ITEM_CATEGORIES.get(number)
            if category and category not in out:
                out.append(category)
    return tuple(out)


def items_from_text(html: str) -> tuple[str, ...]:
    """Recover item numbers from the document when the index omitted them."""
    text = _TAGS.sub(" ", html)
    found: list[str] = []
    for number in _ITEM_IN_TEXT.findall(text):
        if number in ITEM_CATEGORIES and number not in found:
            found.append(number)
    return tuple(found)


def classify_content(html: str) -> tuple[str, ...]:
    """Second-pass keyword categories. Additive detail, never a replacement."""
    text = re.sub(r"\s+", " ", _TAGS.sub(" ", html))
    return tuple(name for name, pattern in CONTENT_PATTERNS if pattern.search(text))


def classify(
    items: list[str], *, body: str | None = None
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return ``(item_numbers, categories)``.

    Falls back to reading item numbers out of the document body when the index
    did not supply them, then adds content keywords. Categories may be empty,
    and that is reported rather than papered over.
    """
    numbers: list[str] = []
    for raw in items:
        for part in re.split(r"[,\s]+", raw):
            number = normalize_item(part)
            if number and number not in numbers:
                numbers.append(number)

    if not numbers and body:
        numbers = list(items_from_text(body))

    categories = list(classify_items(numbers))
    if body:
        for category in classify_content(body):
            if category not in categories:
                categories.append(category)

    return tuple(numbers), tuple(categories)


def is_informative(item_numbers: tuple[str, ...]) -> bool:
    """True if any item is more than administrative.

    A filing whose only items are exhibits or a Reg FD furnishing carries no
    catalyst, and counting it as one inflates the corporate-event category.
    """
    return any(number not in LOW_SIGNAL_ITEMS for number in item_numbers)
