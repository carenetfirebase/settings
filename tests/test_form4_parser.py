"""Form 4 parsing. docs/PHASES.md Phase 2 criterion 8.

Fixtures are hand-built to the schema, not recorded — see
``tests/fixtures/form4/README.md``. These tests prove the parser handles the
documented schema, including its awkward corners; they do not prove it handles
everything filers actually send. That claim needs real recordings.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from pathlib import Path

import pytest

from imt.adapters.records import FilingRef, to_minor
from imt.adapters.sec_form4 import (
    DISCRETIONARY_CODES,
    Form4ParseError,
    describe_code,
    is_discretionary,
    parse_form4,
)

FIXTURES = Path(__file__).parent / "fixtures" / "form4"


def ref(accession: str = "0001234567-26-000001", form_type: str = "4") -> FilingRef:
    return FilingRef(
        accession=accession,
        cik="0000320193",
        form_type=form_type,
        filed_date=date(2026, 8, 16),
        primary_doc_url=f"https://www.sec.gov/Archives/{accession}.xml",
    )


def load(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


class TestMultipleTransactions:
    """Phase 2 criterion 8: a Form 4 with multiple transactions."""

    def parsed(self):
        return parse_form4(load("multi_transaction.xml"), ref=ref())

    def test_parses_every_transaction_and_no_holdings(self) -> None:
        records = self.parsed()
        # Two non-derivative transactions and one derivative. The holdings row
        # reports a position, not a trade, and must not appear.
        assert len(records) == 3
        assert [r.transaction_code for r in records] == ["P", "S", "M"]

    def test_distinguishes_derivative_rows(self) -> None:
        records = self.parsed()
        assert [r.is_derivative for r in records] == [False, False, True]

    def test_computes_value_in_integer_minor_units(self) -> None:
        purchase = self.parsed()[0]
        # 40,000 shares at $60.00 = $2,400,000 = 240,000,000 cents.
        assert purchase.value_minor == 240_000_000
        assert purchase.price_minor == 6000
        assert purchase.currency == "USD"
        assert isinstance(purchase.value_minor, int)

    def test_reads_role_and_relationship_flags(self) -> None:
        purchase = self.parsed()[0]
        assert purchase.is_officer is True
        assert purchase.is_director is False
        assert purchase.role == "Chief Executive Officer"

    def test_transaction_date_is_not_the_filed_date(self) -> None:
        """Both dates are kept and they are different (non-negotiable #5)."""
        purchase = self.parsed()[0]
        assert purchase.transaction_date == date(2026, 8, 14)
        assert purchase.filed_date == date(2026, 8, 16)
        assert purchase.transaction_date != purchase.filed_date


class TestFootnoted10b51:
    """Phase 2 criterion 8: a footnoted 10b5-1.

    A trade under a pre-existing plan was decided months earlier. Reading it as
    fresh conviction is a material misreading, and older filings declare it
    only in footnote prose.
    """

    def test_detects_the_plan_from_footnote_text(self) -> None:
        records = parse_form4(load("footnoted_10b5_1.xml"), ref=ref())
        assert len(records) == 1
        assert records[0].is_10b5_1 is True

    def test_handles_a_default_namespace(self) -> None:
        """Filing agents produce this document both with and without one."""
        records = parse_form4(load("footnoted_10b5_1.xml"), ref=ref())
        assert records[0].cik == "0000320193"

    def test_unpadded_issuer_cik_is_normalized(self) -> None:
        records = parse_form4(load("footnoted_10b5_1.xml"), ref=ref())
        assert records[0].cik == "0000320193"

    def test_absence_of_a_plan_is_unknown_not_false(self) -> None:
        """None and False are different claims. Most filings say nothing."""
        records = parse_form4(load("multi_transaction.xml"), ref=ref())
        assert records[0].is_10b5_1 is None


class TestAmendment:
    """Phase 2 criterion 8: an amendment.

    A 4/A restates an earlier filing. Counting it as a fresh transaction is how
    one insider filing three corrections becomes a three-insider cluster.
    """

    def test_flags_the_amendment_from_the_document(self) -> None:
        records = parse_form4(load("amendment.xml"), ref=ref())
        assert records[0].is_amendment is True

    def test_flags_the_amendment_from_the_index_form_type(self) -> None:
        records = parse_form4(load("multi_transaction.xml"), ref=ref(form_type="4/A"))
        assert all(r.is_amendment for r in records)

    def test_a_plain_filing_is_not_an_amendment(self) -> None:
        records = parse_form4(load("multi_transaction.xml"), ref=ref())
        assert not any(r.is_amendment for r in records)


class TestJointOwners:
    """One decision, one actor.

    A joint filing by an officer and their family trust is one person deciding.
    Cluster detection counts distinct actors, so treating this as two
    independent insiders manufactures a cluster out of a single trade.
    """

    def test_all_owners_collapse_to_one_actor_key(self) -> None:
        records = parse_form4(load("joint_owners.xml"), ref=ref())
        assert len(records) == 1
        assert records[0].actor_key == "0003333333|0004444444"

    def test_actor_key_is_order_independent(self) -> None:
        """Sorted, so the same two owners always produce the same key."""
        key = parse_form4(load("joint_owners.xml"), ref=ref())[0].actor_key
        assert key == "|".join(sorted(key.split("|")))

    def test_relationship_flags_are_combined(self) -> None:
        record = parse_form4(load("joint_owners.xml"), ref=ref())[0]
        assert record.is_officer is True
        assert record.is_ten_percent_owner is True
        assert record.role == "Chief Financial Officer"

    def test_both_names_are_retained(self) -> None:
        record = parse_form4(load("joint_owners.xml"), ref=ref())[0]
        assert "SMITH JOHN" in record.insider_name
        assert "SMITH FAMILY TRUST" in record.insider_name


class TestMissingValues:
    def test_holdings_only_filing_parses_to_zero_rows(self) -> None:
        """A valid document that reports a position, not an error."""
        assert parse_form4(load("holdings_only.xml"), ref=ref()) == []

    def test_footnote_only_price_gives_null_plus_a_reason(self) -> None:
        """CLAUDE.md non-negotiable #2: missing is NULL with a reason code.

        A grant with no stated price is priceless, not free. Storing zero here
        would make a grant look like a $0 purchase.
        """
        record = parse_form4(load("footnote_only_price.xml"), ref=ref())[0]
        assert record.price_minor is None
        assert record.value_minor is None
        assert record.reason_code == "price_not_reported"
        assert record.shares == Decimal("3000")


class TestTransactionCodes:
    def test_only_p_and_s_are_discretionary(self) -> None:
        """SPEC §8. Grants, exercises and tax withholding are compensation
        mechanics; counting them as conviction is the commonest misreading of
        insider data."""
        assert DISCRETIONARY_CODES == {"P", "S"}
        assert is_discretionary("P")
        assert is_discretionary("s")
        for code in ("A", "M", "F", "G"):
            assert not is_discretionary(code)

    def test_codes_are_described_not_guessed(self) -> None:
        assert describe_code("P") == "open-market purchase"
        assert describe_code("F") == "tax withholding"
        assert describe_code("Q") == "unknown code"

    def test_purchase_and_sale_helpers(self) -> None:
        records = parse_form4(load("multi_transaction.xml"), ref=ref())
        assert records[0].is_open_market_purchase
        assert records[1].is_open_market_sale
        # An option exercise is neither, however it looks on a chart.
        assert not records[2].is_open_market_purchase
        assert not records[2].is_open_market_sale


class TestMalformedInput:
    def test_rejects_malformed_xml(self) -> None:
        with pytest.raises(Form4ParseError, match="not well-formed"):
            parse_form4(b"<ownershipDocument><issuer>unclosed", ref=ref())

    def test_rejects_an_html_error_page(self) -> None:
        """EDGAR serves HTML on error, and simple HTML parses as valid XML.

        So "it parsed" is not "it is a Form 4" — the root element check is
        what stops an error page becoming zero silent transactions.
        """
        with pytest.raises(Form4ParseError, match="ownershipDocument"):
            parse_form4(b"<html>404 Not Found</html>", ref=ref())

    def test_rejects_a_document_that_is_not_a_form4(self) -> None:
        with pytest.raises(Form4ParseError, match="ownershipDocument"):
            parse_form4(b"<submission><type>8-K</type></submission>", ref=ref())

    def test_rejects_a_filing_with_no_issuer(self) -> None:
        with pytest.raises(Form4ParseError, match="no issuer CIK"):
            parse_form4(
                b"<ownershipDocument><documentType>4</documentType></ownershipDocument>", ref=ref()
            )


class TestMoneyConversion:
    @pytest.mark.parametrize(
        ("amount", "expected"),
        [
            (Decimal("60.00"), 6000),
            (Decimal("0.01"), 1),
            (Decimal("61.505"), 6151),  # half-up, not banker's
            (Decimal("61.504"), 6150),
            (None, None),
        ],
    )
    def test_to_minor(self, amount: Decimal | None, expected: int | None) -> None:
        assert to_minor(amount) == expected

    def test_result_is_an_int_not_a_float(self) -> None:
        """Money is never a float in this system."""
        assert isinstance(to_minor(Decimal("2400000.00")), int)
