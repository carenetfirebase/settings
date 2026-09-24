"""The V1 read-only routes: signals, sectors, ledger, Lab."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from invest.api.app import create_app
from invest.api.deps import get_readonly_session
from invest.signal_runner import evaluate_ledger, record_signals, scan
from tests.test_signal_runner import AS_OF, market  # noqa: F401 - fixture


@pytest.fixture
def client(market):  # noqa: F811 - the fixture above
    application = create_app()

    def override():
        yield market

    application.dependency_overrides[get_readonly_session] = override
    return TestClient(application)


def test_gate_reports_the_trend_gate_and_volatility(client) -> None:
    body = client.get("/signals/gate", params={"as_of": AS_OF.isoformat()}).json()
    assert body["benchmark"] == "SPY"
    assert body["gate"]["name"] == "trend_gate" and body["gate"]["passed"] is True
    assert 0.5 <= body["volatility"]["multiplier"] <= 1.0


def test_scan_ranks_cards_first_and_explains_every_symbol(client) -> None:
    body = client.get("/signals/scan", params={"as_of": AS_OF.isoformat()}).json()
    assert body["signals"][0]["ticker"] == "NVDA"
    assert body["signals"][0]["status"] == "card"
    assert body["counts"]["card"] == 1
    for signal in body["signals"]:
        assert signal["reasons"] or signal["status"] == "card"
        assert {"name", "sector", "checks", "score"} <= signal.keys()
    assert body["sectors"][0]["ticker"] == "XLK"


def test_scanning_through_the_api_never_records(client, market) -> None:  # noqa: F811
    from sqlalchemy import func, select

    from invest.db.models import SignalRecord

    client.get("/signals/scan", params={"as_of": AS_OF.isoformat()})
    assert market.scalar(select(func.count()).select_from(SignalRecord)) == 0


def test_sectors(client) -> None:
    body = client.get("/markets/sectors", params={"as_of": AS_OF.isoformat()}).json()
    assert len(body["sectors"]) == 11
    tickers = [s["ticker"] for s in body["sectors"]]
    assert tickers.index("XLK") < tickers.index("XLE")


def test_ledger_and_lab(client, market) -> None:  # noqa: F811
    record_signals(market, scan(market, as_of=AS_OF), origin="live")
    evaluate_ledger(market)
    market.commit()

    ledger = client.get("/signals/ledger").json()
    assert ledger["count"] == 1
    entry = ledger["entries"][0]
    assert entry["ticker"] == "NVDA" and entry["origin"] == "live"
    assert entry["outcome_status"] == "pending" and entry["closed"] is False
    assert "survivorship" in ledger["note"]

    assert client.get("/signals/ledger", params={"origin": "backfill"}).json()["count"] == 0
    assert client.get("/signals/ledger", params={"origin": "nonsense"}).status_code == 422

    cal = client.get("/lab/calibration").json()
    assert len(cal["buckets"]) == 5 and cal["monotonic"] is None
    attr = client.get("/lab/attribution").json()
    assert attr["t_stat_bar"] == 3.0
    assert attr["reference"]["signals"] == 1


def test_universe_labels_funds(client) -> None:
    rows = {s["ticker"]: s for s in client.get("/universe").json()["securities"]}
    assert rows["SPY"]["entity_type"] == "fund" and rows["SPY"]["cik"] is None
    assert rows["AAPL"]["entity_type"] == "company"
