"""Deterministic parsing of claim lines.

Nothing here estimates, interpolates, or reconciles. A field that is not
unambiguously present becomes ``None`` with ``needs_review`` set, and the
record surfaces as REVIEW REQUIRED. That is deliberately more annoying
than producing a best guess, because a plausible wrong dollar figure on a
secondary claim is worse than an obvious gap: the gap gets looked at.

Master prompt §8.4 bars the LLM from calculating financial values. The
deterministic path holds the same line — it reads numbers off the
document, it does not derive them. In particular it never computes a
missing field from the others (``billed - paid``, say), because a total
that does not appear on the EOB is this system's arithmetic, not the
payer's, and it would be reported with the same authority as a printed
figure.
"""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation

from .documents import ClaimLine, PatientRecord

#: A currency amount as printed on an EOB. Accepts an optional leading
#: currency symbol, thousands separators, and parenthesised negatives.
_AMOUNT = r"\(?\$?\s*-?[0-9][0-9,]*\.[0-9]{2}\)?"

_LABELLED_AMOUNTS: dict[str, re.Pattern[str]] = {
    "billed": re.compile(
        rf"\b(?:billed|submitted|charge[ds]?|fee)\b[^0-9\-]{{0,20}}(?P<value>{_AMOUNT})",
        re.IGNORECASE,
    ),
    "allowed": re.compile(
        rf"\b(?:allowed|approved|eligible)\b[^0-9\-]{{0,20}}(?P<value>{_AMOUNT})",
        re.IGNORECASE,
    ),
    "paid": re.compile(
        rf"\b(?:paid|payment|plan\s+pays?|carrier\s+paid)\b[^0-9\-]{{0,20}}(?P<value>{_AMOUNT})",
        re.IGNORECASE,
    ),
    "patient_responsibility": re.compile(
        rf"\b(?:patient\s+resp\w*|pat\s+resp|patient\s+portion|coinsurance)\b"
        rf"[^0-9\-]{{0,20}}(?P<value>{_AMOUNT})",
        re.IGNORECASE,
    ),
}

#: ADA procedure codes are D followed by four digits.
_PROCEDURE_RE = re.compile(r"\b(?P<code>D\d{4})\b", re.IGNORECASE)

_SERVICE_DATE_RE = re.compile(
    r"\b(?P<value>\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"
)


def parse_amount(raw: str) -> Decimal | None:
    """Parse a printed currency amount, or return ``None`` if ambiguous."""
    text = raw.strip()
    negative = text.startswith("(") and text.endswith(")")
    text = text.strip("()").replace("$", "").replace(",", "").strip()
    try:
        value = Decimal(text)
    except InvalidOperation:
        return None
    return -value if negative else value


def _first_amount(text: str, pattern: re.Pattern[str]) -> tuple[Decimal | None, bool]:
    """Return ``(value, ambiguous)`` for a labelled amount in ``text``.

    ``ambiguous`` is True when the label appears more than once with
    different values — the parser cannot tell which one is authoritative,
    so it declines to pick.
    """
    matches = pattern.findall(text)
    if not matches:
        return None, False

    values = {parse_amount(match) for match in matches}
    values.discard(None)
    if not values:
        return None, True
    if len(values) > 1:
        return None, True
    return values.pop(), False


def parse_claims(record: PatientRecord) -> tuple[ClaimLine, ...]:
    """Parse claim lines from a patient record.

    One :class:`ClaimLine` per procedure code found. When no procedure
    code is present, a single summary line is produced from the section's
    labelled totals so the record is not silently empty.
    """
    claims: list[ClaimLine] = []

    for line in record.lines:
        procedure = _PROCEDURE_RE.search(line.text)
        if not procedure:
            continue

        amounts: dict[str, Decimal | None] = {}
        ambiguous_fields: list[str] = []
        for field_name, pattern in _LABELLED_AMOUNTS.items():
            value, ambiguous = _first_amount(line.text, pattern)
            amounts[field_name] = value
            if ambiguous:
                ambiguous_fields.append(field_name)

        # Unlabelled amounts on a procedure line are common in tabular
        # layouts. Column position would be needed to attribute them, and
        # guessing the column order is exactly the kind of inference this
        # parser refuses to make.
        if not any(amounts.values()):
            bare = re.findall(_AMOUNT, line.text)
            if bare:
                ambiguous_fields.append("unlabelled_amounts")

        service_date = _SERVICE_DATE_RE.search(line.text)

        claims.append(
            ClaimLine(
                procedure_code=procedure.group("code").upper(),
                service_date=service_date.group("value") if service_date else None,
                billed=amounts.get("billed"),
                allowed=amounts.get("allowed"),
                paid=amounts.get("paid"),
                patient_responsibility=amounts.get("patient_responsibility"),
                needs_review=bool(ambiguous_fields),
                review_reason=(
                    f"could not attribute: {', '.join(sorted(set(ambiguous_fields)))}"
                    if ambiguous_fields
                    else None
                ),
            )
        )

    if claims:
        return tuple(claims)

    # No procedure codes: fall back to section totals, flagged for review
    # because a claim with no procedure code is not a claim this parser
    # understands.
    section_text = "\n".join(line.text for line in record.lines)
    amounts = {}
    for field_name, pattern in _LABELLED_AMOUNTS.items():
        value, _ = _first_amount(section_text, pattern)
        amounts[field_name] = value

    return (
        ClaimLine(
            billed=amounts.get("billed"),
            allowed=amounts.get("allowed"),
            paid=amounts.get("paid"),
            patient_responsibility=amounts.get("patient_responsibility"),
            needs_review=True,
            review_reason="no ADA procedure code found in this section",
        ),
    )
