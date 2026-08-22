"""Schema-level guarantees: append-only enforcement, point-in-time keys,
multi-source coexistence, and the firewall default.
"""

from __future__ import annotations

from datetime import date

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError, IntegrityError

from invest.db.enums import DataQualityFlag, FirewallStatus, ValueType
from invest.db.models import (
    APPEND_ONLY_TABLES,
    Entity,
    Fundamental,
    PoliticalTrade,
    PriceObservation,
    ResearchSnapshot,
    Security,
)


@pytest.fixture
def security(db_session) -> Security:
    entity = Entity(name="Test Co", cik="0000000123", source="test")
    db_session.add(entity)
    db_session.flush()
    sec = Security(entity_id=entity.id, ticker="TSTC", exchange="NYSE")
    db_session.add(sec)
    db_session.commit()
    return sec


def test_all_expected_tables_exist(db_engine) -> None:
    expected = {
        "entities",
        "securities",
        "entity_relationships",
        "price_observations",
        "fundamentals",
        "filings",
        "insider_transactions",
        "political_trades",
        "macro_observations",
        "data_conflicts",
        "research_snapshots",
        "workflow_jobs",
    }
    with db_engine.connect() as conn:
        present = set(
            conn.execute(
                text("SELECT tablename FROM pg_tables WHERE schemaname='public'")
            ).scalars()
        )
    assert expected <= present


# --------------------------------------------------------------------------
# Ground rule 6: append-only
# --------------------------------------------------------------------------


def test_price_update_is_rejected_by_trigger(db_session, security) -> None:
    db_session.add(
        PriceObservation(
            security_id=security.id, obs_date=date(2026, 1, 5), close=100, source="stooq"
        )
    )
    db_session.commit()

    row = db_session.scalars(select(PriceObservation)).one()
    row.close = 999
    with pytest.raises(DBAPIError, match="append-only"):
        db_session.commit()
    db_session.rollback()


def test_price_delete_is_rejected_by_trigger(db_session, security) -> None:
    obs = PriceObservation(
        security_id=security.id, obs_date=date(2026, 1, 5), close=100, source="stooq"
    )
    db_session.add(obs)
    db_session.commit()

    db_session.delete(obs)
    with pytest.raises(DBAPIError, match="append-only"):
        db_session.commit()
    db_session.rollback()


@pytest.mark.parametrize("table", sorted(APPEND_ONLY_TABLES))
def test_append_only_trigger_installed_on_every_protected_table(db_engine, table) -> None:
    with db_engine.connect() as conn:
        triggers = set(
            conn.execute(
                text(
                    "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid "
                    "WHERE c.relname = :t AND NOT t.tgisinternal"
                ),
                {"t": table},
            ).scalars()
        )
    assert f"trg_{table}_append_only" in triggers


def test_research_snapshot_is_immutable(db_session, security) -> None:
    snap = ResearchSnapshot(
        entity_id=security.entity_id,
        security_id=security.id,
        snapshot_date=date(2026, 1, 5),
        as_of_date=date(2026, 1, 5),
        model_version="HF-QM-v1.0",
        components_json={"a": 1},
        inputs_json={"b": 2},
    )
    db_session.add(snap)
    db_session.commit()

    snap.investment_quality_score = 50
    with pytest.raises(DBAPIError, match="append-only"):
        db_session.commit()
    db_session.rollback()


# --------------------------------------------------------------------------
# Multi-source coexistence and point-in-time
# --------------------------------------------------------------------------


def test_two_sources_may_hold_the_same_day(db_session, security) -> None:
    """UNIQUE(security_id, obs_date, source) — the gate compares them later."""
    db_session.add_all(
        [
            PriceObservation(
                security_id=security.id, obs_date=date(2026, 1, 5), close=100, source="stooq"
            ),
            PriceObservation(
                security_id=security.id, obs_date=date(2026, 1, 5), close=100.02, source="yfinance"
            ),
        ]
    )
    db_session.commit()
    assert len(db_session.scalars(select(PriceObservation)).all()) == 2


def test_same_source_same_day_is_rejected(db_session, security) -> None:
    db_session.add(
        PriceObservation(
            security_id=security.id, obs_date=date(2026, 1, 5), close=100, source="stooq"
        )
    )
    db_session.commit()
    db_session.add(
        PriceObservation(
            security_id=security.id, obs_date=date(2026, 1, 5), close=101, source="stooq"
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_negative_price_is_rejected(db_session, security) -> None:
    db_session.add(
        PriceObservation(
            security_id=security.id, obs_date=date(2026, 1, 6), close=-1, source="stooq"
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_fundamental_requires_filed_date(db_session, security) -> None:
    """The point-in-time key is not optional."""
    db_session.add(
        Fundamental(
            entity_id=security.entity_id,
            metric_name="Revenues",
            metric_value=1000,
            unit="USD",
            period_end=date(2025, 12, 31),
            filed_date=None,
            source="sec_edgar",
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_restatement_is_a_new_row_not_an_edit(db_session, security) -> None:
    """Same period, later filing -> both rows coexist, so a backtest dated
    between the two filings sees only the original figure.
    """
    original = Fundamental(
        entity_id=security.entity_id,
        metric_name="Revenues",
        metric_value=1000,
        unit="USD",
        period_end=date(2025, 12, 31),
        fiscal_period="FY",
        filed_date=date(2026, 2, 1),
        accession_number="0000000000-26-000001",
        source="sec_edgar",
    )
    restated = Fundamental(
        entity_id=security.entity_id,
        metric_name="Revenues",
        metric_value=950,
        unit="USD",
        period_end=date(2025, 12, 31),
        fiscal_period="FY",
        filed_date=date(2026, 8, 1),
        accession_number="0000000000-26-000042",
        source="sec_edgar",
    )
    db_session.add_all([original, restated])
    db_session.commit()

    as_of = date(2026, 5, 1)
    visible = db_session.scalars(
        select(Fundamental)
        .where(Fundamental.entity_id == security.entity_id)
        .where(Fundamental.filed_date <= as_of)
    ).all()
    assert len(visible) == 1
    assert float(visible[0].metric_value) == 1000.0


def test_value_type_vocabulary_is_enforced(db_session, security) -> None:
    db_session.add(
        PriceObservation(
            security_id=security.id,
            obs_date=date(2026, 1, 7),
            close=10,
            source="stooq",
            value_type="wishful_thinking",
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


def test_defaults_are_server_side(db_session, security) -> None:
    """Raw SQL must get the same defaults the ORM does."""
    db_session.execute(
        text(
            "INSERT INTO price_observations (security_id, obs_date, close, source) "
            "VALUES (:s, :d, :c, :src)"
        ),
        {"s": security.id, "d": date(2026, 1, 8), "c": 12.5, "src": "raw_sql"},
    )
    db_session.commit()
    row = db_session.scalars(
        select(PriceObservation).where(PriceObservation.source == "raw_sql")
    ).one()
    assert row.value_type == ValueType.OBSERVED
    assert row.data_quality_flag == DataQualityFlag.OK
    assert row.currency == "USD"


# --------------------------------------------------------------------------
# Firewall
# --------------------------------------------------------------------------


def test_political_trade_defaults_to_investigate_only(db_session) -> None:
    db_session.execute(
        text(
            "INSERT INTO political_trades "
            "(politician_name, transaction_date, disclosure_date, source) "
            "VALUES (:n, :t, :d, :s)"
        ),
        {"n": "A Representative", "t": date(2026, 1, 2), "d": date(2026, 2, 2), "s": "house_clerk"},
    )
    db_session.commit()
    trade = db_session.scalars(select(PoliticalTrade)).one()
    assert trade.firewall_status == FirewallStatus.INVESTIGATE_ONLY


def test_disclosure_cannot_precede_transaction(db_session) -> None:
    db_session.add(
        PoliticalTrade(
            politician_name="A Senator",
            transaction_date=date(2026, 3, 1),
            disclosure_date=date(2026, 2, 1),
            source="senate_efd",
        )
    )
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()
