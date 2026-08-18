from __future__ import annotations

import pytest
from sqlalchemy import select

from invest.db.enums import DataQualityFlag
from invest.db.models import Entity, Security
from invest.security_master import (
    ResolutionError,
    normalize_cik,
    resolve,
    seed_universe,
    verify_ciks,
)
from invest.universe import SEED_UNIVERSE, by_ticker


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("320193", "0000320193"),
        ("0000320193", "0000320193"),
        ("CIK0000320193", "0000320193"),
        (320193, "0000320193"),
        ("  789019 ", "0000789019"),
    ],
)
def test_normalize_cik_handles_edgar_variants(raw, expected) -> None:
    assert normalize_cik(raw) == expected


def test_normalize_cik_rejects_junk() -> None:
    with pytest.raises(ValueError):
        normalize_cik("NOT-A-CIK")


def test_seed_universe_is_idempotent(db_session) -> None:
    first = seed_universe(db_session)
    db_session.commit()
    second = seed_universe(db_session)
    db_session.commit()

    assert len(first) == len(SEED_UNIVERSE)
    assert {s.security_id for s in first} == {s.security_id for s in second}
    assert len(db_session.scalars(select(Security)).all()) == len(SEED_UNIVERSE)
    assert len(db_session.scalars(select(Entity)).all()) == len(SEED_UNIVERSE)


def test_seeded_rows_are_flagged_unverified(db_session) -> None:
    """A hardcoded CIK is a claim, not a fact, until EDGAR confirms it."""
    seed_universe(db_session)
    db_session.commit()
    for entity in db_session.scalars(select(Entity)).all():
        assert entity.data_quality_flag == DataQualityFlag.UNVERIFIED_BOOTSTRAP


def test_resolve_returns_the_full_handle(db_session) -> None:
    seed_universe(db_session)
    db_session.commit()

    resolved = resolve(db_session, "aapl")  # case-insensitive
    seed = by_ticker("AAPL")
    assert seed is not None
    assert resolved.ticker == "AAPL"
    assert resolved.cik == seed.cik
    assert resolved.stooq_symbol == "aapl.us"
    assert resolved.currency == "USD"
    assert resolved.entity_id > 0


def test_resolve_raises_for_unknown_ticker(db_session) -> None:
    seed_universe(db_session)
    db_session.commit()
    with pytest.raises(ResolutionError, match="not in the security master"):
        resolve(db_session, "NOSUCHTICKER")


def test_is_financial_flag_marks_banks(db_session) -> None:
    """Selects the Altman Z variant downstream."""
    seed_universe(db_session)
    db_session.commit()
    assert resolve(db_session, "JPM").is_financial is True
    assert resolve(db_session, "AAPL").is_financial is False


def test_verify_ciks_confirms_matching_entries(db_session) -> None:
    seed_universe(db_session)
    db_session.commit()

    authority = {e.ticker: e.cik for e in SEED_UNIVERSE}
    results = verify_ciks(db_session, authority)
    db_session.commit()

    assert {r.status for r in results} == {"confirmed"}
    for entity in db_session.scalars(select(Entity)).all():
        assert entity.data_quality_flag == DataQualityFlag.OK


def test_verify_ciks_corrects_a_wrong_seed(db_session) -> None:
    """The whole point of the verify step: a bad seed gets fixed, loudly."""
    seed_universe(db_session)
    db_session.commit()

    authority = {e.ticker: e.cik for e in SEED_UNIVERSE}
    authority["AAPL"] = "0000999999"

    results = verify_ciks(db_session, authority)
    db_session.commit()

    aapl = next(r for r in results if r.ticker == "AAPL")
    assert aapl.status == "corrected"
    assert aapl.authoritative_cik == "0000999999"
    assert resolve(db_session, "AAPL").cik == "0000999999"


def test_verify_ciks_does_not_promote_unconfirmed_tickers(db_session) -> None:
    """A ticker the authority has never heard of keeps its unverified flag —
    absence of contradiction is not confirmation.
    """
    seed_universe(db_session)
    db_session.commit()

    authority = {e.ticker: e.cik for e in SEED_UNIVERSE if e.ticker != "KO"}
    results = verify_ciks(db_session, authority)
    db_session.commit()

    ko = next(r for r in results if r.ticker == "KO")
    assert ko.status == "missing_from_authority"

    ko_entity = db_session.scalars(select(Entity).where(Entity.name.like("%Coca-Cola%"))).one()
    assert ko_entity.data_quality_flag == DataQualityFlag.UNVERIFIED_BOOTSTRAP


def test_seed_universe_has_no_duplicate_tickers_or_ciks() -> None:
    tickers = [e.ticker for e in SEED_UNIVERSE]
    ciks = [e.cik for e in SEED_UNIVERSE]
    assert len(tickers) == len(set(tickers))
    assert len(ciks) == len(set(ciks))


def test_seed_ciks_are_ten_digit_padded() -> None:
    for entry in SEED_UNIVERSE:
        assert len(entry.cik) == 10
        assert entry.cik.isdigit()
