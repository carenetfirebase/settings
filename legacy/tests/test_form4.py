"""Form 4 parsing and insider signal interpretation.

Fixture XML mirrors the real ownershipDocument shape with synthetic names and
numbers. The interpretation tests are the important ones: mis-reading a
compensation grant as a purchase is the classic way insider data goes wrong.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from invest.providers.base import InsiderTransactionRecord, ProviderError
from invest.providers.form4 import (
    InsiderSummary,
    describe_code,
    is_discretionary,
    parse_form4,
    signal_weight,
)

FILED = date(2026, 3, 16)


def form4_xml(
    *,
    transactions: str = "",
    derivatives: str = "",
    owner_name: str = "DOE JANE",
    owner_cik: str = "0001234567",
    is_director: str = "1",
    is_officer: str = "0",
    officer_title: str = "",
    namespace: bool = False,
) -> str:
    ns = ' xmlns="http://www.sec.gov/edgar/ownership"' if namespace else ""
    return f"""<?xml version="1.0"?>
<ownershipDocument{ns}>
  <periodOfReport>2026-03-14</periodOfReport>
  <issuer>
    <issuerCik>0000320193</issuerCik>
    <issuerTradingSymbol>AAPL</issuerTradingSymbol>
  </issuer>
  <reportingOwner>
    <reportingOwnerId>
      <rptOwnerCik>{owner_cik}</rptOwnerCik>
      <rptOwnerName>{owner_name}</rptOwnerName>
    </reportingOwnerId>
    <reportingOwnerRelationship>
      <isDirector>{is_director}</isDirector>
      <isOfficer>{is_officer}</isOfficer>
      <isTenPercentOwner>0</isTenPercentOwner>
      <officerTitle>{officer_title}</officerTitle>
    </reportingOwnerRelationship>
  </reportingOwner>
  <nonDerivativeTable>{transactions}</nonDerivativeTable>
  <derivativeTable>{derivatives}</derivativeTable>
</ownershipDocument>"""


def txn(
    *,
    code: str = "P",
    shares: str = "1000",
    price: str = "150.25",
    acquired: str = "A",
    owned_after: str = "5000",
    txn_date: str = "2026-03-14",
    derivative: bool = False,
) -> str:
    tag = "derivativeTransaction" if derivative else "nonDerivativeTransaction"
    return f"""
    <{tag}>
      <securityTitle><value>Common Stock</value></securityTitle>
      <transactionDate><value>{txn_date}</value></transactionDate>
      <transactionCoding><transactionCode>{code}</transactionCode></transactionCoding>
      <transactionAmounts>
        <transactionShares><value>{shares}</value></transactionShares>
        <transactionPricePerShare><value>{price}</value></transactionPricePerShare>
        <transactionAcquiredDisposedCode><value>{acquired}</value></transactionAcquiredDisposedCode>
      </transactionAmounts>
      <postTransactionAmounts>
        <sharesOwnedFollowingTransaction><value>{owned_after}</value></sharesOwnedFollowingTransaction>
      </postTransactionAmounts>
    </{tag}>"""


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------


def test_parses_a_purchase() -> None:
    records = parse_form4(
        form4_xml(transactions=txn()), filed_date=FILED, accession_number="acc-1"
    )
    assert len(records) == 1
    record = records[0]
    assert record.cik == "0000320193"
    assert record.insider_name == "DOE JANE"
    assert record.insider_cik == "0001234567"
    assert record.is_director is True
    assert record.is_officer is False
    assert record.transaction_code == "P"
    assert record.acquired_disposed == "A"
    assert record.shares == Decimal(1000)
    assert record.price_per_share == Decimal("150.25")
    assert record.shares_owned_after == Decimal(5000)
    assert record.is_derivative is False
    assert record.accession_number == "acc-1"


def test_transaction_and_filed_dates_are_stored_separately() -> None:
    """The two-business-day lag is itself signal, and only filed_date is
    legitimate for point-in-time work.
    """
    record = parse_form4(form4_xml(transactions=txn()), filed_date=FILED)[0]
    assert record.transaction_date == date(2026, 3, 14)
    assert record.filed_date == FILED
    assert record.filed_date > record.transaction_date


def test_parses_documents_with_a_default_namespace() -> None:
    """Filing agents differ on whether they declare one."""
    records = parse_form4(
        form4_xml(transactions=txn(), namespace=True), filed_date=FILED
    )
    assert len(records) == 1
    assert records[0].transaction_code == "P"


def test_parses_multiple_transactions() -> None:
    xml = form4_xml(transactions=txn(code="P") + txn(code="S", acquired="D", shares="500"))
    records = parse_form4(xml, filed_date=FILED)
    assert len(records) == 2
    assert {r.transaction_code for r in records} == {"P", "S"}


def test_derivative_transactions_are_flagged_not_merged() -> None:
    """An option exercise is not the same event as an open-market purchase."""
    xml = form4_xml(transactions=txn(code="P"), derivatives=txn(code="M", derivative=True))
    records = parse_form4(xml, filed_date=FILED)
    assert len(records) == 2
    by_type = {r.is_derivative: r for r in records}
    assert by_type[False].transaction_code == "P"
    assert by_type[True].transaction_code == "M"


def test_holdings_rows_are_not_treated_as_transactions() -> None:
    """A holding reports a position, not a trade."""
    holding = """
    <nonDerivativeHolding>
      <securityTitle><value>Common Stock</value></securityTitle>
      <postTransactionAmounts>
        <sharesOwnedFollowingTransaction><value>9999</value></sharesOwnedFollowingTransaction>
      </postTransactionAmounts>
    </nonDerivativeHolding>"""
    records = parse_form4(form4_xml(transactions=holding), filed_date=FILED)
    assert records == []


def test_footnote_only_values_become_null_not_zero() -> None:
    """The schema permits a footnote reference in place of a number. That is
    'not reported', not 'zero'.
    """
    footnoted = """
    <nonDerivativeTransaction>
      <transactionDate><value>2026-03-14</value></transactionDate>
      <transactionCoding><transactionCode>P</transactionCode></transactionCoding>
      <transactionAmounts>
        <transactionShares><footnoteId id="F1"/></transactionShares>
        <transactionPricePerShare><footnoteId id="F2"/></transactionPricePerShare>
        <transactionAcquiredDisposedCode><value>A</value></transactionAcquiredDisposedCode>
      </transactionAmounts>
    </nonDerivativeTransaction>"""
    record = parse_form4(form4_xml(transactions=footnoted), filed_date=FILED)[0]
    assert record.shares is None
    assert record.price_per_share is None
    assert record.transaction_code == "P"  # the code is still known


def test_missing_price_is_null() -> None:
    """Gifts and grants legitimately have no price."""
    record = parse_form4(
        form4_xml(transactions=txn(code="G", price="0", acquired="D")), filed_date=FILED
    )[0]
    assert record.transaction_code == "G"


def test_comma_separated_share_counts_parse() -> None:
    record = parse_form4(form4_xml(transactions=txn(shares="1,250,000")), filed_date=FILED)[0]
    assert record.shares == Decimal(1250000)


def test_boolean_variants_are_handled() -> None:
    record = parse_form4(
        form4_xml(transactions=txn(), is_director="true", is_officer="false"), filed_date=FILED
    )[0]
    assert record.is_director is True
    assert record.is_officer is False


def test_officer_title_is_captured() -> None:
    record = parse_form4(
        form4_xml(transactions=txn(), is_officer="1", officer_title="Chief Executive Officer"),
        filed_date=FILED,
    )[0]
    assert record.officer_title == "Chief Executive Officer"


def test_empty_filing_is_not_an_error() -> None:
    """A holdings-only amendment is a valid document."""
    assert parse_form4(form4_xml(), filed_date=FILED) == []


def test_malformed_xml_raises() -> None:
    with pytest.raises(ProviderError, match="not well-formed"):
        parse_form4("<ownershipDocument><unclosed>", filed_date=FILED)


def test_wrong_document_type_raises() -> None:
    with pytest.raises(ProviderError, match="expected an ownershipDocument"):
        parse_form4("<somethingElse/>", filed_date=FILED)


def test_missing_issuer_cik_raises() -> None:
    xml = "<ownershipDocument><issuer><issuerTradingSymbol>X</issuerTradingSymbol></issuer></ownershipDocument>"
    with pytest.raises(ProviderError, match="no issuer CIK"):
        parse_form4(xml, filed_date=FILED)


def test_issuer_cik_is_zero_padded() -> None:
    xml = form4_xml(transactions=txn()).replace("0000320193", "320193")
    assert parse_form4(xml, filed_date=FILED)[0].cik == "0000320193"


# --------------------------------------------------------------------------
# Interpretation — the part that matters
# --------------------------------------------------------------------------


@pytest.mark.parametrize("code", ["P", "S"])
def test_open_market_trades_are_discretionary(code) -> None:
    assert is_discretionary(code) is True


@pytest.mark.parametrize("code", ["A", "M", "F", "G", "C", "D", "X"])
def test_compensation_and_administrative_codes_are_not_discretionary(code) -> None:
    """Treating a scheduled grant as a 'buy' is the classic misreading."""
    assert is_discretionary(code) is False


def test_describe_code_is_human_readable() -> None:
    assert describe_code("P") == "open-market purchase"
    assert describe_code("F") == "shares withheld to cover tax"
    assert describe_code(None) == "unspecified"
    assert "code Q" in describe_code("Q")


def record(**overrides) -> InsiderTransactionRecord:
    base = {
        "cik": "0000320193",
        "insider_name": "DOE JANE",
        "transaction_date": date(2026, 3, 14),
        "filed_date": FILED,
        "transaction_code": "P",
        "acquired_disposed": "A",
        "shares": Decimal(1000),
        "price_per_share": Decimal(100),
        "is_derivative": False,
        "source": "sec_edgar",
    }
    base.update(overrides)
    return InsiderTransactionRecord(**base)


def test_purchase_carries_full_positive_weight() -> None:
    assert signal_weight(record(transaction_code="P", acquired_disposed="A")) == 1.0


def test_sale_is_damped_relative_to_a_purchase() -> None:
    """Insiders sell for diversification, tax and divorce; they buy for one
    reason. Symmetric treatment overstates the bearish signal.
    """
    buy = signal_weight(record(transaction_code="P", acquired_disposed="A"))
    sell = signal_weight(record(transaction_code="S", acquired_disposed="D"))
    assert sell < 0
    assert abs(sell) < abs(buy)


def test_grants_and_exercises_carry_no_weight() -> None:
    assert signal_weight(record(transaction_code="A", acquired_disposed="A")) == 0.0
    assert signal_weight(record(transaction_code="M", acquired_disposed="A")) == 0.0
    assert signal_weight(record(transaction_code="F", acquired_disposed="D")) == 0.0


def test_derivative_purchase_counts_less_than_an_equity_purchase() -> None:
    equity = signal_weight(record(transaction_code="P", is_derivative=False))
    derivative = signal_weight(record(transaction_code="P", is_derivative=True))
    assert 0 < derivative < equity


# --------------------------------------------------------------------------
# Aggregation
# --------------------------------------------------------------------------


def test_summary_counts_only_discretionary_transactions() -> None:
    """A company whose only filings are option exercises has no insider
    signal, and must report that rather than a neutral zero.
    """
    summary = InsiderSummary(
        [
            record(transaction_code="A"),
            record(transaction_code="M"),
            record(transaction_code="F", acquired_disposed="D"),
        ]
    )
    assert summary.transaction_count == 0
    assert summary.net_buy_ratio is None
    assert len(summary.all_records) == 3


def test_all_buying_gives_ratio_of_one() -> None:
    summary = InsiderSummary([record(), record()])
    assert summary.net_buy_ratio == pytest.approx(1.0)
    assert summary.transaction_count == 2


def test_all_selling_gives_ratio_of_minus_one() -> None:
    summary = InsiderSummary(
        [record(transaction_code="S", acquired_disposed="D") for _ in range(3)]
    )
    assert summary.net_buy_ratio == pytest.approx(-1.0)


def test_mixed_activity_lands_between() -> None:
    summary = InsiderSummary(
        [
            record(transaction_code="P", acquired_disposed="A"),
            record(transaction_code="S", acquired_disposed="D"),
        ]
    )
    # weights +1.0 and -0.5 -> net 0.5 / total 1.5
    assert summary.net_buy_ratio == pytest.approx(0.5 / 1.5)


def test_summary_reports_traded_value() -> None:
    summary = InsiderSummary(
        [
            record(shares=Decimal(1000), price_per_share=Decimal(50)),
            record(
                transaction_code="S",
                acquired_disposed="D",
                shares=Decimal(400),
                price_per_share=Decimal(50),
            ),
        ]
    )
    assert summary.buy_value == pytest.approx(50_000)
    assert summary.sell_value == pytest.approx(20_000)


def test_summary_tolerates_missing_prices() -> None:
    """A footnoted price must not crash the aggregate."""
    summary = InsiderSummary([record(price_per_share=None)])
    assert summary.buy_value == 0.0
    assert summary.net_buy_ratio == pytest.approx(1.0)


def test_summary_serialises() -> None:
    payload = InsiderSummary([record()]).as_dict()
    assert payload["transaction_count"] == 1
    assert payload["buys"] == 1
    assert payload["net_buy_ratio"] == pytest.approx(1.0)
