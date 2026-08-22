"""Read-only local API.

The structural tests matter most here: that every route is a GET, and that the
database itself refuses writes. Those are the two claims that make an
unauthenticated local API defensible, and neither should be able to quietly
stop being true.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from invest.analysis import analyze, save_snapshot
from invest.api.app import create_app
from invest.api.deps import get_readonly_session
from invest.db.models import (
    Fundamental,
    InsiderTransaction,
    MacroObservation,
    PoliticalTrade,
    PriceObservation,
)
from invest.security_master import resolve, seed_universe

AS_OF = date(2026, 6, 15)


@pytest.fixture
def client(db_session):
    """A TestClient wired to the test session.

    The dependency override hands back the same transaction the fixture owns,
    so data written by a test is visible to the API without committing.
    """
    application = create_app()

    def override():
        yield db_session

    application.dependency_overrides[get_readonly_session] = override
    return TestClient(application)


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def add_prices(session, security_id, *, days: int = 400) -> None:
    day = AS_OF - timedelta(days=days)
    price = 100.0
    while day < AS_OF:
        if day.weekday() < 5:
            price *= 1.0008
            session.add(
                PriceObservation(
                    security_id=security_id,
                    obs_date=day,
                    open=price * 0.995,
                    high=price * 1.01,
                    low=price * 0.99,
                    close=price,
                    volume=1_000_000,
                    source="stooq",
                )
            )
        day += timedelta(days=1)
    session.flush()


def add_fundamentals(session, entity_id, *, years: int = 3) -> None:
    for i in range(years):
        year = 2023 + i
        for metric, value in (
            ("Revenues", 1000.0 * (1.08**i)),
            ("NetIncomeLoss", 150.0 * (1.08**i)),
            ("Assets", 2000.0),
            ("StockholdersEquity", 1100.0),
            ("SharesOutstanding", 100.0),
        ):
            session.add(
                Fundamental(
                    entity_id=entity_id,
                    metric_name=metric,
                    metric_value=value,
                    unit="USD" if "Shares" not in metric else "shares",
                    period_start=date(year, 1, 1),
                    period_end=date(year, 12, 31),
                    fiscal_year=year,
                    fiscal_period="FY",
                    filed_date=date(year + 1, 2, 15),
                    form_type="10-K",
                    accession_number=f"acc-{year}-{metric}",
                    source="sec_edgar",
                )
            )
    session.flush()


# --------------------------------------------------------------------------
# Structural guarantees
# --------------------------------------------------------------------------


def test_every_route_is_read_only() -> None:
    """'Read-only' must not be able to quietly stop being true.

    Enumerates the route table; any POST/PUT/PATCH/DELETE fails the build.
    Mounts are checked separately, since a Mount carries no `.methods` and
    would otherwise slip through this loop unexamined.
    """
    from starlette.routing import Mount
    from starlette.staticfiles import StaticFiles

    application = create_app()
    offending: list[str] = []

    for route in application.routes:
        if isinstance(route, Mount):
            # The only mount we permit is static assets, which serve GET/HEAD.
            assert isinstance(route.app, StaticFiles), (
                f"Unexpected non-static mount at {route.path}: {type(route.app)}"
            )
            continue
        methods = getattr(route, "methods", set()) or set()
        mutating = methods - {"GET", "HEAD", "OPTIONS"}
        if mutating:
            offending.append(f"{getattr(route, 'path', route)}: {sorted(mutating)}")

    assert not offending, f"Non-read-only routes found: {offending}"


# --------------------------------------------------------------------------
# Offline docs — no third-party calls
# --------------------------------------------------------------------------


def test_docs_page_references_no_external_hosts(client) -> None:
    """A local research tool must not fetch its own docs assets from a CDN.

    The stock FastAPI docs page pulls CSS/JS from cdn.jsdelivr.net and a
    favicon from fastapi.tiangolo.com. Both are replaced with local paths, so
    /docs works air-gapped and renders nothing third-party alongside your
    research data.
    """
    body = client.get("/docs").text
    assert "cdn.jsdelivr.net" not in body
    assert "fastapi.tiangolo.com" not in body
    assert "/static/swagger/swagger-ui-bundle.js" in body
    assert "/static/swagger/swagger-ui.css" in body


def test_swagger_assets_are_served_locally(client) -> None:
    css = client.get("/static/swagger/swagger-ui.css")
    js = client.get("/static/swagger/swagger-ui-bundle.js")
    assert css.status_code == 200
    assert js.status_code == 200
    assert len(css.content) > 10_000
    assert len(js.content) > 100_000


def test_database_itself_refuses_writes(db_engine) -> None:
    """The API's session runs inside SET TRANSACTION READ ONLY, so a bug in a
    handler cannot write. Discipline that depends on nobody erring is not
    discipline.
    """
    from sqlalchemy.exc import DBAPIError, InternalError

    session_gen = get_readonly_session()
    session = next(session_gen)
    try:
        with pytest.raises((DBAPIError, InternalError)) as exc_info:
            session.execute(
                text("INSERT INTO entities (name, source) VALUES ('Nope', 'test')")
            )
        assert "read-only" in str(exc_info.value).lower()
    finally:
        session_gen.close()


def test_health(client) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["read_only"] is True


def test_unknown_ticker_is_a_404_with_guidance(client, aapl) -> None:
    response = client.get("/securities/NOSUCHTICKER")
    assert response.status_code == 404
    assert "security master" in response.json()["detail"]


# --------------------------------------------------------------------------
# Universe
# --------------------------------------------------------------------------


def test_universe_lists_securities(client, aapl) -> None:
    response = client.get("/universe")
    assert response.status_code == 200
    body = response.json()
    assert body["count"] >= 20
    tickers = {s["ticker"] for s in body["securities"]}
    assert "AAPL" in tickers


def test_universe_warns_about_unverified_ciks(client, aapl) -> None:
    """Seeded CIKs are claims until EDGAR confirms them, and the API says so."""
    body = client.get("/universe").json()
    assert body["meta"]["note"] is not None
    assert "not been verified" in body["meta"]["note"]


def test_security_detail(client, aapl) -> None:
    body = client.get("/securities/aapl").json()
    assert body["ticker"] == "AAPL"
    assert body["cik"] == aapl.cik
    assert body["is_financial"] is False


def test_financial_flag_is_exposed(client, aapl) -> None:
    """Drives the Altman variant; a client should be able to see it."""
    assert client.get("/securities/JPM").json()["is_financial"] is True


# --------------------------------------------------------------------------
# Prices
# --------------------------------------------------------------------------


def test_prices_are_returned(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.flush()

    body = client.get("/securities/AAPL/prices").json()
    assert body["count"] > 0
    assert body["bars"][0]["close"] is not None
    assert "NOT dividend-adjusted" in body["adjustment_note"]


def test_prices_respect_as_of(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.flush()

    early = client.get("/securities/AAPL/prices", params={"as_of": "2026-01-15"}).json()
    late = client.get("/securities/AAPL/prices", params={"as_of": "2026-06-01"}).json()
    assert early["count"] < late["count"]
    assert early["meta"]["as_of"] == "2026-01-15"


def test_quarantined_prices_are_never_served(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id, days=30)
    db_session.add(
        PriceObservation(
            security_id=aapl.security_id,
            obs_date=AS_OF - timedelta(days=1),
            close=999_999,
            source="stooq",
            data_quality_flag="quarantined",
        )
    )
    db_session.flush()

    body = client.get("/securities/AAPL/prices").json()
    assert all(bar["close"] < 1000 for bar in body["bars"])


def test_empty_price_history_is_an_empty_list_not_an_error(client, aapl) -> None:
    body = client.get("/securities/AAPL/prices").json()
    assert body["count"] == 0
    assert body["bars"] == []


# --------------------------------------------------------------------------
# Fundamentals
# --------------------------------------------------------------------------


def test_fundamentals_are_returned_with_filed_dates(client, db_session, aapl) -> None:
    add_fundamentals(db_session, aapl.entity_id)
    db_session.flush()

    body = client.get("/securities/AAPL/fundamentals").json()
    assert "Revenues" in body["series"]
    point = body["series"]["Revenues"][0]
    assert point["filed_date"]
    assert point["value_type"] == "observed"


def test_missing_metrics_are_listed_explicitly(client, db_session, aapl) -> None:
    """A client must be able to tell absent from zero."""
    add_fundamentals(db_session, aapl.entity_id)
    db_session.flush()

    body = client.get("/securities/AAPL/fundamentals").json()
    assert "InventoryNet" in body["metrics_missing"]
    assert "InventoryNet" not in body["series"]


def test_fundamentals_are_point_in_time(client, db_session, aapl) -> None:
    add_fundamentals(db_session, aapl.entity_id)
    db_session.flush()

    early = client.get(
        "/securities/AAPL/fundamentals", params={"as_of": "2024-06-01", "metric": "Revenues"}
    ).json()
    late = client.get(
        "/securities/AAPL/fundamentals", params={"as_of": "2026-06-01", "metric": "Revenues"}
    ).json()
    assert len(early["series"].get("Revenues", [])) < len(late["series"]["Revenues"])


def test_restatement_serves_the_figure_public_at_the_time(client, db_session, aapl) -> None:
    db_session.add_all(
        [
            Fundamental(
                entity_id=aapl.entity_id,
                metric_name="Revenues",
                metric_value=1000,
                unit="USD",
                period_end=date(2025, 12, 31),
                fiscal_period="FY",
                filed_date=date(2026, 2, 1),
                accession_number="orig",
                source="sec_edgar",
            ),
            Fundamental(
                entity_id=aapl.entity_id,
                metric_name="Revenues",
                metric_value=950,
                unit="USD",
                period_end=date(2025, 12, 31),
                fiscal_period="FY",
                filed_date=date(2026, 8, 1),
                accession_number="restated",
                source="sec_edgar",
            ),
        ]
    )
    db_session.flush()

    before = client.get(
        "/securities/AAPL/fundamentals", params={"as_of": "2026-05-01", "metric": "Revenues"}
    ).json()
    after = client.get(
        "/securities/AAPL/fundamentals", params={"as_of": "2026-09-01", "metric": "Revenues"}
    ).json()

    assert before["series"]["Revenues"][0]["value"] == 1000.0
    assert after["series"]["Revenues"][0]["value"] == 950.0


# --------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------


def test_analysis_returns_three_decomposed_scores(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    add_fundamentals(db_session, aapl.entity_id)
    db_session.flush()

    body = client.get("/securities/AAPL/analysis", params={"as_of": "2026-06-15"}).json()
    for key in ("investment_quality", "trade_setup", "confidence"):
        assert key in body
        assert body[key]["components"]
        for component in body[key]["components"]:
            assert "weight" in component
            assert "detail" in component


def test_analysis_never_returns_a_composite_score(client, db_session, aapl) -> None:
    """The three scores are deliberately kept apart."""
    add_prices(db_session, aapl.security_id)
    db_session.flush()
    body = client.get("/securities/AAPL/analysis").json()
    assert "composite" not in body
    assert "overall" not in body


def test_analysis_names_the_premium_data_gap(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.flush()
    body = client.get("/securities/AAPL/analysis").json()
    assert body["premium_data_dependent"]
    assert any("analyst" in item for item in body["premium_data_dependent"])


def test_analysis_with_no_data_returns_nulls_not_zeros(client, aapl) -> None:
    body = client.get("/securities/AAPL/analysis").json()
    assert body["investment_quality"]["value"] is None
    assert body["investment_quality"]["reliable"] is False


def test_analysis_does_not_write_a_snapshot(client, db_session, aapl) -> None:
    """The API never writes, even when running the full pipeline."""
    from invest.db.models import ResearchSnapshot

    add_prices(db_session, aapl.security_id)
    db_session.flush()
    before = db_session.query(ResearchSnapshot).count()

    client.get("/securities/AAPL/analysis")

    assert db_session.query(ResearchSnapshot).count() == before


def test_report_endpoint_returns_text(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.flush()
    body = client.get("/securities/AAPL/report").json()
    assert "INVESTMENT RESEARCH REPORT" in body["report_text"]
    assert "PREMIUM-DATA DEPENDENT" in body["report_text"]


# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------


def test_snapshots_are_listed_and_fetchable(client, db_session, aapl) -> None:
    add_prices(db_session, aapl.security_id)
    db_session.flush()
    result = analyze(db_session, "AAPL", as_of=AS_OF)
    snapshot = save_snapshot(db_session, result)
    db_session.flush()

    listing = client.get("/snapshots").json()
    assert listing["count"] == 1

    detail = client.get(f"/snapshots/{snapshot.id}").json()
    assert detail["snapshot"]["model_version"].startswith("HF-QM-v")
    assert detail["inputs"]["as_of"] == AS_OF.isoformat()
    assert detail["report_text"]


def test_missing_snapshot_is_a_404(client, aapl) -> None:
    assert client.get("/snapshots/999999").status_code == 404


# --------------------------------------------------------------------------
# Insider
# --------------------------------------------------------------------------


def test_insider_separates_conviction_from_compensation(client, db_session, aapl) -> None:
    for i, (code, ad) in enumerate([("P", "A"), ("A", "A"), ("M", "A")]):
        db_session.add(
            InsiderTransaction(
                entity_id=aapl.entity_id,
                security_id=aapl.security_id,
                insider_name=f"Officer {i}",
                transaction_date=AS_OF - timedelta(days=20),
                filed_date=AS_OF - timedelta(days=18),
                transaction_code=code,
                acquired_disposed=ad,
                shares=1000,
                price_per_share=120,
                accession_number=f"f4-{i}",
                source="sec_edgar",
            )
        )
    db_session.flush()

    body = client.get(
        "/securities/AAPL/insider", params={"as_of": AS_OF.isoformat()}
    ).json()
    assert body["total_filings"] == 3
    assert body["discretionary_trades"] == 1
    assert body["net_buy_ratio"] == pytest.approx(1.0)

    codes = {t["transaction_code"]: t for t in body["transactions"]}
    assert codes["P"]["is_discretionary"] is True
    assert codes["A"]["is_discretionary"] is False
    assert "grant" in codes["A"]["code_meaning"]


def test_insider_exposes_the_disclosure_lag(client, db_session, aapl) -> None:
    db_session.add(
        InsiderTransaction(
            entity_id=aapl.entity_id,
            security_id=aapl.security_id,
            insider_name="Officer A",
            transaction_date=AS_OF - timedelta(days=20),
            filed_date=AS_OF - timedelta(days=18),
            transaction_code="P",
            acquired_disposed="A",
            shares=1000,
            price_per_share=120,
            accession_number="f4-lag",
            source="sec_edgar",
        )
    )
    db_session.flush()
    body = client.get("/securities/AAPL/insider", params={"as_of": AS_OF.isoformat()}).json()
    assert body["transactions"][0]["disclosure_lag_days"] == 2


def test_no_insider_data_reports_null_not_neutral(client, aapl) -> None:
    body = client.get("/securities/AAPL/insider").json()
    assert body["total_filings"] == 0
    assert body["net_buy_ratio"] is None


# --------------------------------------------------------------------------
# Disclosures — firewalled
# --------------------------------------------------------------------------


def test_disclosures_are_served_with_the_firewall_stated(client, db_session, aapl) -> None:
    db_session.add(
        PoliticalTrade(
            politician_name="Rep A",
            chamber="house",
            security_id=aapl.security_id,
            ticker_raw="AAPL",
            transaction_type="purchase",
            transaction_date=AS_OF - timedelta(days=60),
            disclosure_date=AS_OF - timedelta(days=20),
            amount_range_low=1001,
            amount_range_high=15000,
            source="house_clerk",
        )
    )
    db_session.flush()

    body = client.get(
        "/securities/AAPL/disclosures", params={"as_of": AS_OF.isoformat()}
    ).json()
    assert body["count"] == 1
    assert body["firewall_status"] == "investigate_only"
    assert "contributes NOTHING to any score" in body["firewall_note"]
    assert body["disclosures"][0]["disclosure_lag_days"] == 40


def test_disclosure_amounts_keep_both_bracket_bounds(client, db_session, aapl) -> None:
    """No midpoint — that would be a number nobody reported."""
    db_session.add(
        PoliticalTrade(
            politician_name="Rep B",
            security_id=aapl.security_id,
            transaction_date=AS_OF - timedelta(days=60),
            disclosure_date=AS_OF - timedelta(days=20),
            amount_range_low=50001,
            amount_range_high=100000,
            source="house_clerk",
        )
    )
    db_session.flush()
    disclosure = client.get(
        "/securities/AAPL/disclosures", params={"as_of": AS_OF.isoformat()}
    ).json()["disclosures"][0]
    assert disclosure["amount_range_low"] == 50001
    assert disclosure["amount_range_high"] == 100000


def test_disclosures_do_not_change_the_analysis(client, db_session, aapl) -> None:
    """The firewall, restated at the API boundary."""
    add_prices(db_session, aapl.security_id)
    db_session.flush()
    before = client.get("/securities/AAPL/analysis").json()

    for i in range(20):
        db_session.add(
            PoliticalTrade(
                politician_name=f"Rep {i}",
                security_id=aapl.security_id,
                transaction_date=AS_OF - timedelta(days=60),
                disclosure_date=AS_OF - timedelta(days=20),
                amount_range_low=1_000_000,
                amount_range_high=5_000_000,
                source="house_clerk",
            )
        )
    db_session.flush()
    after = client.get("/securities/AAPL/analysis").json()

    assert after["trade_setup"]["value"] == before["trade_setup"]["value"]
    assert after["investment_quality"]["value"] == before["investment_quality"]["value"]
    assert after["confidence"]["value"] == before["confidence"]["value"]


# --------------------------------------------------------------------------
# Regime and stats
# --------------------------------------------------------------------------


def test_regime_reports_insufficient_data_when_empty(client) -> None:
    body = client.get("/regime").json()
    assert body["regime"] == "insufficient_data"
    assert body["risk_score"] is None
    assert "Not a forecast" in body["note"]


def test_regime_classifies_from_stored_macro(client, db_session) -> None:
    for series_id, value in (("T10Y2Y", -0.4), ("BAMLH0A0HYM2", 7.5), ("VIXCLS", 30.0)):
        db_session.add(
            MacroObservation(
                series_id=series_id,
                obs_date=AS_OF - timedelta(days=3),
                value=value,
                unit="percent",
                source="fred",
            )
        )
    db_session.flush()

    body = client.get("/regime", params={"as_of": AS_OF.isoformat()}).json()
    assert body["regime"] == "stress"
    assert body["reliable"] is True
    assert len(body["signals"]) == 5


def test_stats_counts_rows(client, aapl) -> None:
    body = client.get("/stats").json()
    assert body["tables"]["securities"] >= 20
    assert "political_trades" in body["tables"]


def test_conflicts_endpoint(client, db_session, aapl) -> None:
    from invest.db.models import DataConflict

    db_session.add(
        DataConflict(
            table_name="price_observations",
            security_id=aapl.security_id,
            conflict_type="cross_source_disagreement",
            severity="warning",
            source_a="stooq",
            value_a=100,
            source_b="yfinance",
            value_b=120,
            detail="[test] sources disagree",
        )
    )
    db_session.flush()

    body = client.get("/conflicts").json()
    assert body["count"] == 1
    assert body["conflicts"][0]["source_a"] == "stooq"


# --------------------------------------------------------------------------
# Documentation
# --------------------------------------------------------------------------


def test_openapi_schema_is_generated(client) -> None:
    schema = client.get("/openapi.json").json()
    assert schema["info"]["title"] == "invest — research API"
    assert "/universe" in schema["paths"]


def test_api_description_states_the_conventions(client) -> None:
    schema = client.get("/openapi.json").json()
    description = schema["info"]["description"]
    assert "Nothing here is investment advice" in description
    assert "`null` never means zero" in description
    assert "firewalled" in description


def test_head_is_answered_wherever_get_is(client, aapl) -> None:
    """RFC 9110: a general-purpose server must support HEAD alongside GET.

    FastAPI's APIRoute does not add it the way Starlette's router does, so
    without the fix every endpoint answered `curl -I` with 405.
    """
    for path in ("/health", "/universe", "/securities/AAPL"):
        response = client.head(path)
        assert response.status_code == 200, f"HEAD {path} -> {response.status_code}"
        assert response.content == b""


def test_head_reports_the_same_length_as_get(client, aapl) -> None:
    """The point of HEAD is asking the size without paying for the body."""
    head = client.head("/universe")
    get = client.get("/universe")
    assert head.headers["content-length"] == get.headers["content-length"]


def test_mutating_verbs_are_still_refused(client, aapl) -> None:
    """Adding HEAD must not have widened anything else."""
    for method in ("post", "put", "patch", "delete"):
        response = getattr(client, method)("/universe")
        assert response.status_code == 405
        assert "GET" in response.headers.get("allow", "")


def test_openapi_contract_declares_only_get(client) -> None:
    """HEAD is handled by middleware precisely so the published contract stays
    clean. If a future change widens routes instead, this catches the spec
    noise it would create.
    """
    paths = client.get("/openapi.json").json()["paths"]
    methods = {m.upper() for ops in paths.values() for m in ops}
    assert methods == {"GET"}, f"contract declares more than GET: {methods}"
