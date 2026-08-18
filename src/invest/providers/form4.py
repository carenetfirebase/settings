"""SEC Form 4 (statement of changes in beneficial ownership) XML parsing.

Form 4 is where corporate insiders disclose their own trades. It is the one
"smart money" dataset that is genuinely free, genuinely public, and genuinely
timely — insiders must file within two business days of the transaction.

## Document shape

    <ownershipDocument>
      <periodOfReport>2026-03-14</periodOfReport>
      <issuer><issuerCik>..</issuerCik><issuerTradingSymbol>..</issuerTradingSymbol></issuer>
      <reportingOwner>
        <reportingOwnerId><rptOwnerCik/><rptOwnerName/></reportingOwnerId>
        <reportingOwnerRelationship>
          <isDirector>1</isDirector><isOfficer>0</isOfficer>
          <isTenPercentOwner>0</isTenPercentOwner><officerTitle/>
        </reportingOwnerRelationship>
      </reportingOwner>
      <nonDerivativeTable>
        <nonDerivativeTransaction>
          <transactionDate><value>2026-03-14</value></transactionDate>
          <transactionCoding><transactionCode>P</transactionCode></transactionCoding>
          <transactionAmounts>
            <transactionShares><value>1000</value></transactionShares>
            <transactionPricePerShare><value>150.25</value></transactionPricePerShare>
            <transactionAcquiredDisposedCode><value>A</value></...>
          </transactionAmounts>
          <postTransactionAmounts>
            <sharesOwnedFollowingTransaction><value>5000</value></...>
          </postTransactionAmounts>
        </nonDerivativeTransaction>
      </nonDerivativeTable>
      <derivativeTable>...</derivativeTable>
    </ownershipDocument>

Nearly every leaf is wrapped in a `<value>` element, because the schema allows
a `<footnoteId>` sibling instead — a filer may report "shares: see footnote"
with no number at all. Those become NULL rather than zero.

## What matters for interpretation

* **transactionCode is everything.** `P` (open-market purchase) and `S` (open-
  market sale) are discretionary decisions. `A` (grant/award), `M` (option
  exercise), `F` (shares withheld for tax), and `G` (gift) are not — treating
  a compensation grant as a "buy" is the single most common way insider data
  is misread. `signal_weight()` encodes that distinction.
* **transaction_date and filed_date are stored separately.** Only filed_date is
  legitimate for point-in-time work; the gap between them is itself signal.
* **Derivative transactions are flagged, not merged.** An option exercise is
  not the same event as buying stock on the open market.
"""

from __future__ import annotations

import logging
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from xml.etree import ElementTree

from invest.providers.base import InsiderTransactionRecord, ProviderError

logger = logging.getLogger(__name__)

SOURCE_NAME = "sec_edgar"


# --------------------------------------------------------------------------
# Transaction codes
# --------------------------------------------------------------------------

#: Open-market, discretionary transactions. These are the ones that carry
#: information: the insider chose to move their own money.
DISCRETIONARY_CODES = frozenset({"P", "S"})

#: Compensation, administrative, and non-discretionary events. Counting these
#: as conviction is the classic Form 4 misreading — an executive receiving a
#: scheduled equity grant has not expressed a view on the price.
NON_DISCRETIONARY_CODES = frozenset({"A", "M", "F", "G", "C", "D", "I", "J", "K", "U", "W", "X", "Z"})

CODE_MEANINGS: dict[str, str] = {
    "P": "open-market purchase",
    "S": "open-market sale",
    "A": "grant, award or other acquisition",
    "D": "disposition to the issuer",
    "F": "shares withheld to cover tax",
    "M": "exercise or conversion of a derivative",
    "G": "bona fide gift",
    "C": "conversion of a derivative security",
    "I": "discretionary transaction",
    "J": "other acquisition or disposition",
    "K": "equity swap",
    "U": "disposition due to a tender of shares",
    "W": "acquisition or disposition by will or inheritance",
    "X": "exercise of an in-the-money derivative",
    "Z": "deposit into or withdrawal from a voting trust",
}


def is_discretionary(code: str | None) -> bool:
    """Whether the insider actually chose to trade at this price."""
    return code is not None and code.upper() in DISCRETIONARY_CODES


def describe_code(code: str | None) -> str:
    if code is None:
        return "unspecified"
    return CODE_MEANINGS.get(code.upper(), f"code {code}")


def signal_weight(record: InsiderTransactionRecord) -> float:
    """Signed conviction weight in [-1, 1], or 0.0 for non-informative events.

    Sales are deliberately damped relative to purchases. Insiders sell for
    diversification, tax bills, divorces and house purchases; they buy for
    exactly one reason. Treating the two symmetrically overstates the bearish
    signal, which is a well-documented flaw in naive insider models.
    """
    if not is_discretionary(record.transaction_code):
        return 0.0
    if record.is_derivative:
        # A derivative purchase is a real decision but a different instrument;
        # count it at reduced weight rather than as an equity buy.
        return 0.5 if record.acquired_disposed == "A" else -0.25
    if record.acquired_disposed == "A":
        return 1.0
    if record.acquired_disposed == "D":
        return -0.5
    return 0.0


# --------------------------------------------------------------------------
# XML helpers
# --------------------------------------------------------------------------


def _strip_ns(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _find(element, path: str):
    """Namespace-agnostic find over a slash-separated path.

    Form 4 documents appear both with and without a default namespace
    depending on filing agent, so matching on the local name is the only
    approach that works across all of them.
    """
    current = element
    for part in path.split("/"):
        found = None
        for child in list(current):
            if _strip_ns(child.tag) == part:
                found = child
                break
        if found is None:
            return None
        current = found
    return current


def _text(element, path: str) -> str | None:
    node = _find(element, path)
    if node is None:
        return None
    text = (node.text or "").strip()
    return text or None


def _value(element, path: str) -> str | None:
    """Read `<path><value>X</value></path>`.

    Falls back to the element's own text: some filing agents omit the `<value>`
    wrapper. Returns None when the element carries only a footnote reference,
    which is the schema's way of saying "no number is being reported".
    """
    node = _find(element, path)
    if node is None:
        return None
    value_node = _find(node, "value")
    if value_node is not None:
        text = (value_node.text or "").strip()
        return text or None
    text = (node.text or "").strip()
    return text or None


def _decimal(raw: str | None) -> Decimal | None:
    if raw is None:
        return None
    try:
        return Decimal(raw.replace(",", ""))
    except (InvalidOperation, ValueError):
        return None


def _date(raw: str | None) -> date | None:
    if raw is None:
        return None
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%Y%m%d"):
        try:
            return datetime.strptime(raw[:10], fmt).date()
        except ValueError:
            continue
    return None


def _bool(raw: str | None) -> bool | None:
    """Form 4 booleans arrive as 1/0, true/false, or Y/N depending on agent."""
    if raw is None:
        return None
    normalized = raw.strip().lower()
    if normalized in ("1", "true", "y", "yes"):
        return True
    if normalized in ("0", "false", "n", "no"):
        return False
    return None


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------


def parse_form4(
    xml_text: str,
    *,
    filed_date: date,
    accession_number: str | None = None,
) -> list[InsiderTransactionRecord]:
    """Parse one Form 4 document into transaction records.

    `filed_date` comes from the submissions index rather than the document
    body: the document reports the *period*, and only the filing date is a
    legitimate point-in-time key.

    A filing with no transactions (a holdings-only amendment) returns [] —
    that is a valid document, not an error.
    """
    try:
        root = ElementTree.fromstring(xml_text)
    except ElementTree.ParseError as exc:
        raise ProviderError(f"{SOURCE_NAME}: Form 4 is not well-formed XML: {exc}") from exc

    if _strip_ns(root.tag) != "ownershipDocument":
        raise ProviderError(
            f"{SOURCE_NAME}: expected an ownershipDocument, got {_strip_ns(root.tag)!r}"
        )

    issuer_cik = _text(root, "issuer/issuerCik")
    if issuer_cik is None:
        raise ProviderError(f"{SOURCE_NAME}: Form 4 has no issuer CIK")
    issuer_cik = issuer_cik.zfill(10)

    # A single Form 4 may carry several reporting owners (a joint filing).
    owners = [child for child in list(root) if _strip_ns(child.tag) == "reportingOwner"]
    if owners:
        owner = owners[0]
        insider_name = _text(owner, "reportingOwnerId/rptOwnerName") or "UNKNOWN"
        insider_cik_raw = _text(owner, "reportingOwnerId/rptOwnerCik")
        insider_cik = insider_cik_raw.zfill(10) if insider_cik_raw else None
        is_director = _bool(_text(owner, "reportingOwnerRelationship/isDirector"))
        is_officer = _bool(_text(owner, "reportingOwnerRelationship/isOfficer"))
        is_ten_pct = _bool(_text(owner, "reportingOwnerRelationship/isTenPercentOwner"))
        officer_title = _text(owner, "reportingOwnerRelationship/officerTitle")
    else:
        insider_name = "UNKNOWN"
        insider_cik = None
        is_director = is_officer = is_ten_pct = None
        officer_title = None

    if len(owners) > 1:
        logger.info(
            "%s: Form 4 %s has %d reporting owners; attributing to the first (%s)",
            SOURCE_NAME,
            accession_number,
            len(owners),
            insider_name,
        )

    period = _date(_text(root, "periodOfReport"))
    records: list[InsiderTransactionRecord] = []

    for table_name, is_derivative in (
        ("nonDerivativeTable", False),
        ("derivativeTable", True),
    ):
        table = _find(root, table_name)
        if table is None:
            continue

        for node in list(table):
            local = _strip_ns(node.tag)
            # Holdings rows report a position, not a trade. Skipped: a holding
            # is not a transaction and must not be counted as one.
            if not local.endswith("Transaction"):
                continue

            transaction_date = _date(_value(node, "transactionDate")) or period
            if transaction_date is None:
                logger.info(
                    "%s: skipping a transaction with no usable date in %s",
                    SOURCE_NAME,
                    accession_number,
                )
                continue

            shares = _decimal(_value(node, "transactionAmounts/transactionShares"))
            price = _decimal(_value(node, "transactionAmounts/transactionPricePerShare"))
            owned_after = _decimal(
                _value(node, "postTransactionAmounts/sharesOwnedFollowingTransaction")
            )
            code = _text(node, "transactionCoding/transactionCode")
            acquired_disposed = _value(
                node, "transactionAmounts/transactionAcquiredDisposedCode"
            )

            try:
                records.append(
                    InsiderTransactionRecord(
                        cik=issuer_cik,
                        insider_name=insider_name,
                        insider_cik=insider_cik,
                        is_director=is_director,
                        is_officer=is_officer,
                        is_ten_pct_owner=is_ten_pct,
                        officer_title=officer_title,
                        transaction_date=transaction_date,
                        filed_date=filed_date,
                        transaction_code=(code.upper() if code else None),
                        acquired_disposed=(
                            acquired_disposed.upper()[:1] if acquired_disposed else None
                        ),
                        shares=shares,
                        price_per_share=price,
                        shares_owned_after=owned_after,
                        is_derivative=is_derivative,
                        accession_number=accession_number,
                        source=SOURCE_NAME,
                    )
                )
            except ValueError as exc:
                logger.info("%s: rejected a Form 4 row in %s: %s", SOURCE_NAME, accession_number, exc)

    return records


# --------------------------------------------------------------------------
# Aggregation for the Trade Setup score
# --------------------------------------------------------------------------


class InsiderSummary:
    """Net insider conviction over a window.

    Only discretionary open-market transactions count. `transaction_count` is
    the number of those, not the number of Form 4 rows — a company whose only
    filings are option exercises has zero insider signal, and the score must
    report it as unavailable rather than neutral.
    """

    def __init__(self, records: list[InsiderTransactionRecord]) -> None:
        self.all_records = records
        self.discretionary = [r for r in records if is_discretionary(r.transaction_code)]
        self.buys = [r for r in self.discretionary if r.acquired_disposed == "A"]
        self.sells = [r for r in self.discretionary if r.acquired_disposed == "D"]

    @property
    def transaction_count(self) -> int:
        return len(self.discretionary)

    @property
    def buy_value(self) -> float:
        return sum(
            float(r.shares * r.price_per_share)
            for r in self.buys
            if r.shares is not None and r.price_per_share is not None
        )

    @property
    def sell_value(self) -> float:
        return sum(
            float(r.shares * r.price_per_share)
            for r in self.sells
            if r.shares is not None and r.price_per_share is not None
        )

    @property
    def net_buy_ratio(self) -> float | None:
        """(weighted buys - weighted sells) / total, in [-1, 1].

        None when there are no discretionary transactions — which is different
        from a neutral 0.0, and the score treats it as such.
        """
        if not self.discretionary:
            return None
        weights = [signal_weight(r) for r in self.discretionary]
        total = sum(abs(w) for w in weights)
        if total == 0:
            return None
        return sum(weights) / total

    def as_dict(self) -> dict:
        return {
            "transaction_count": self.transaction_count,
            "total_filings": len(self.all_records),
            "buys": len(self.buys),
            "sells": len(self.sells),
            "buy_value": self.buy_value,
            "sell_value": self.sell_value,
            "net_buy_ratio": self.net_buy_ratio,
        }
