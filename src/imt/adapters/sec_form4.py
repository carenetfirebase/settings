"""Form 4 / Form 144 XML parsing. Pure: bytes in, records out, no I/O.

Ported from the prior build (docs/INHERITED.md) with three additions the
original lacked and SPEC §8 requires:

* **10b5-1 detection.** A purchase made under a pre-existing trading plan is a
  much weaker signal than a discretionary one — the decision was made months
  earlier. Modern filings carry an explicit flag; older ones only say so in a
  footnote, so both are checked.
* **Amendment flag.** ``4/A`` restates an earlier filing. Counting an
  amendment as a fresh transaction is how one insider becomes three.
* **``actor_key``.** Identifies the decision maker rather than the document, so
  cluster detection counts independent people (SPEC §8).

Two structural facts about Form 4 XML that dictate the shape of this module:
filing agents produce it both with and without a default namespace, so every
lookup matches on the local tag name; and a numeric element may carry only a
footnote reference, which is the schema's way of saying "no number is being
reported" — that is NULL with a reason code, never zero.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from xml.etree import ElementTree

from imt.adapters.records import FilingRef, InsiderTransactionRecord, to_minor
from imt.core.logging import get_logger
from imt.entities.identifiers import normalize_cik

log = get_logger(__name__)

SOURCE_ID = "sec_edgar"

#: SPEC §8. These are not interchangeable and the difference drives the score.
CODE_MEANINGS: dict[str, str] = {
    "P": "open-market purchase",
    "S": "open-market sale",
    "A": "grant or award",
    "M": "option exercise",
    "F": "tax withholding",
    "G": "gift",
    "C": "conversion",
    "D": "disposition to issuer",
    "E": "expiration (short)",
    "H": "expiration (long)",
    "I": "discretionary transaction",
    "J": "other acquisition or disposition",
    "K": "equity swap",
    "L": "small acquisition",
    "O": "out-of-the-money exercise",
    "U": "tender of shares",
    "W": "will or inheritance",
    "X": "in-the-money exercise",
    "Z": "voting trust deposit",
}

#: Only these two reflect a decision to move money at a market price. Grants,
#: exercises and tax withholding are compensation mechanics, and counting them
#: as conviction is the most common way insider data is misread.
DISCRETIONARY_CODES = frozenset({"P", "S"})

# Filers write this with a hyphen, an en dash or an em dash; all three appear
# in real footnote prose, which is why the character class is not "just a
# hyphen". noqa: the ambiguous characters are the point.
_RULE_10B5_1 = re.compile(r"10b5[\s\-–—]?1", re.IGNORECASE)


class Form4ParseError(ValueError):
    """The document is not a Form 4, or is not well-formed."""


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _find(element: ElementTree.Element | None, path: str) -> ElementTree.Element | None:
    """Namespace-agnostic find over a slash-separated path."""
    if element is None:
        return None
    current: ElementTree.Element = element
    for part in path.split("/"):
        found: ElementTree.Element | None = None
        for child in current:
            if _local(child.tag) == part:
                found = child
                break
        if found is None:
            return None
        current = found
    return current


def _text(element: ElementTree.Element | None, path: str) -> str | None:
    node = _find(element, path)
    if node is None:
        return None
    return (node.text or "").strip() or None


def _value(element: ElementTree.Element | None, path: str) -> str | None:
    """Read ``<path><value>X</value></path>``.

    Falls back to the element's own text, because some agents omit the wrapper.
    Returns None when the element carries only a ``<footnoteId>`` — that means
    no number is being reported, and inventing one would violate CLAUDE.md
    non-negotiable #2.
    """
    node = _find(element, path)
    if node is None:
        return None
    value_node = _find(node, "value")
    if value_node is not None:
        return (value_node.text or "").strip() or None
    return (node.text or "").strip() or None


def _decimal(raw: str | None) -> Decimal | None:
    if raw is None:
        return None
    try:
        return Decimal(raw.replace(",", "").replace("$", ""))
    except (InvalidOperation, ValueError):
        return None


def _date(raw: str | None) -> date | None:
    if raw is None:
        return None
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%Y%m%d"):
        try:
            return datetime.strptime(raw[:10], fmt).date()  # noqa: DTZ007
        except ValueError:
            continue
    return None


def _bool(raw: str | None) -> bool | None:
    """Form 4 booleans arrive as 1/0, true/false, or Y/N depending on agent."""
    if raw is None:
        return None
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "y", "yes"}:
        return True
    if normalized in {"0", "false", "n", "no"}:
        return False
    return None


def _footnote_text(root: ElementTree.Element) -> str:
    """All footnote bodies concatenated, for 10b5-1 detection on older filings."""
    parts: list[str] = []
    for element in root.iter():
        if _local(element.tag) == "footnote":
            parts.append("".join(element.itertext()))
    return " ".join(parts)


def _role(is_officer: bool, is_director: bool, is_ten_pct: bool, title: str | None) -> str | None:
    """Coarse role label. The fine-grained weighting happens in features/."""
    if title:
        return title.strip()
    if is_officer:
        return "officer"
    if is_director:
        return "director"
    if is_ten_pct:
        return "10% owner"
    return None


def _detect_10b5_1(
    node: ElementTree.Element, root: ElementTree.Element, footnotes: str
) -> bool | None:
    """Explicit flag first, footnote text second, unknown third.

    ``None`` means the filing did not say — which is different from saying no,
    and is stored as NULL rather than False. Most pre-2023 filings are None.
    """
    for path in (
        "transactionCoding/rule10b5-1Flag",
        "transactionCoding/equitySwapInvolved",
    ):
        if path.endswith("rule10b5-1Flag"):
            explicit = _bool(_value(node, path)) or _bool(_text(node, path))
            if explicit is not None:
                return explicit
    for element in root.iter():
        if _local(element.tag) in {"aff10b5One", "rule10b5-1Flag"}:
            explicit = _bool((element.text or "").strip())
            if explicit is not None:
                return explicit
    if footnotes and _RULE_10B5_1.search(footnotes):
        return True
    return None


def parse_form4(payload: bytes, *, ref: FilingRef) -> list[InsiderTransactionRecord]:
    """Parse one Form 4 document into transaction records.

    ``ref.filed_date`` comes from the index, not the document body: the
    document reports a *period*, and only the filing date is a legitimate
    point-in-time key (SPEC §7).

    A holdings-only filing returns ``[]``. That is a valid document, not an
    error — a filing that reports a position rather than a trade.
    """
    try:
        root = ElementTree.fromstring(payload)
    except ElementTree.ParseError as exc:
        raise Form4ParseError(f"Form 4 {ref.accession} is not well-formed XML: {exc}") from exc

    if _local(root.tag) != "ownershipDocument":
        raise Form4ParseError(
            f"Form 4 {ref.accession}: expected ownershipDocument, got {_local(root.tag)!r}"
        )

    issuer_raw = _text(root, "issuer/issuerCik")
    if issuer_raw is None:
        raise Form4ParseError(f"Form 4 {ref.accession} has no issuer CIK")
    issuer_cik = normalize_cik(issuer_raw)

    owners = [child for child in root if _local(child.tag) == "reportingOwner"]
    names: list[str] = []
    ciks: list[str] = []
    is_officer = is_director = is_ten_pct = False
    title: str | None = None

    for owner in owners:
        name = _text(owner, "reportingOwnerId/rptOwnerName")
        if name:
            names.append(name.strip())
        owner_cik = _text(owner, "reportingOwnerId/rptOwnerCik")
        if owner_cik:
            ciks.append(normalize_cik(owner_cik))
        # Relationship flags are OR-ed across owners: a joint filing by an
        # officer and their family trust is an officer's transaction.
        is_officer |= bool(_bool(_text(owner, "reportingOwnerRelationship/isOfficer")))
        is_director |= bool(_bool(_text(owner, "reportingOwnerRelationship/isDirector")))
        is_ten_pct |= bool(_bool(_text(owner, "reportingOwnerRelationship/isTenPercentOwner")))
        title = title or _text(owner, "reportingOwnerRelationship/officerTitle")

    insider_name = " & ".join(names) if names else "UNKNOWN"
    insider_cik = ciks[0] if ciks else None

    # One decision, one actor. A joint filing by a person and their trust must
    # not count as two independent insiders in cluster detection, so the key is
    # built from every owner on the document, sorted for stability.
    actor_key = "|".join(sorted(ciks)) if ciks else f"name:{insider_name.upper()}"

    is_amendment = ref.is_amendment or (_text(root, "documentType") or "").endswith("/A")
    period = _date(_text(root, "periodOfReport"))
    footnotes = _footnote_text(root)

    records: list[InsiderTransactionRecord] = []

    for table_name, is_derivative in (("nonDerivativeTable", False), ("derivativeTable", True)):
        table = _find(root, table_name)
        if table is None:
            continue

        for node in table:
            # Holdings rows report a position, not a trade.
            if not _local(node.tag).endswith("Transaction"):
                continue

            transaction_date = _date(_value(node, "transactionDate")) or period
            if transaction_date is None:
                log.info("form4.no_transaction_date", accession=ref.accession)
                continue

            code = (_text(node, "transactionCoding/transactionCode") or "").strip().upper()
            if not code:
                log.info("form4.no_transaction_code", accession=ref.accession)
                continue

            shares = _decimal(_value(node, "transactionAmounts/transactionShares"))
            price = _decimal(_value(node, "transactionAmounts/transactionPricePerShare"))
            owned_after = _decimal(
                _value(node, "postTransactionAmounts/sharesOwnedFollowingTransaction")
            )
            acquired = _value(node, "transactionAmounts/transactionAcquiredDisposedCode")

            # Missing is NULL plus a reason, never zero. A grant with no stated
            # price is genuinely priceless, not free.
            reason_code: str | None = None
            value_minor: int | None = None
            if shares is not None and price is not None:
                value_minor = to_minor(shares * price)
            elif shares is None:
                reason_code = "shares_not_reported"
            else:
                reason_code = "price_not_reported"

            records.append(
                InsiderTransactionRecord(
                    cik=issuer_cik,
                    accession=ref.accession,
                    insider_name=insider_name,
                    insider_cik=insider_cik,
                    actor_key=actor_key,
                    transaction_code=code,
                    transaction_date=transaction_date,
                    filed_date=ref.filed_date,
                    shares=shares,
                    price_minor=to_minor(price),
                    value_minor=value_minor,
                    shares_owned_after=owned_after,
                    is_officer=is_officer,
                    is_director=is_director,
                    is_ten_percent_owner=is_ten_pct,
                    role=_role(is_officer, is_director, is_ten_pct, title),
                    is_derivative=is_derivative,
                    is_amendment=is_amendment,
                    is_10b5_1=_detect_10b5_1(node, root, footnotes),
                    acquired_disposed=(acquired or "").strip().upper()[:1] or None,
                    reason_code=reason_code,
                )
            )

    return records


def describe_code(code: str) -> str:
    return CODE_MEANINGS.get(code.upper(), "unknown code")


def is_discretionary(code: str) -> bool:
    return code.upper() in DISCRETIONARY_CODES
