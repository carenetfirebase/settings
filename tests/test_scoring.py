"""Scoring engine, including the political-trade firewall."""

from __future__ import annotations

import ast
import inspect
from pathlib import Path

import pytest

from invest.db.models import FIREWALLED_TABLES
from invest.engines import scoring
from invest.engines.fundamentals import (
    FinancialInputs,
    altman_z_score,
    beneish_m_score,
    piotroski_f_score,
)
from invest.engines.scoring import (
    MODEL_VERSION,
    ConfidenceInputs,
    QualityInputs,
    Score,
    ScoreSet,
    SubScore,
    TradeSetupInputs,
    confidence_score,
    investment_quality_score,
    trade_setup_score,
)

# --------------------------------------------------------------------------
# Score plumbing
# --------------------------------------------------------------------------


def test_weighted_average_hand_computed() -> None:
    score = Score(
        "Test",
        [
            SubScore("a", 80.0, 0.5, ""),
            SubScore("b", 60.0, 0.5, ""),
        ],
    )
    assert score.value == pytest.approx(70.0)  # 80*0.5 + 60*0.5
    assert score.coverage == pytest.approx(1.0)


def test_missing_component_renormalises_rather_than_scoring_zero() -> None:
    """Treating a missing input as zero would make an unknown look like a
    failure. The honesty cost is paid by `coverage`, not by the score.
    """
    score = Score(
        "Test",
        [
            SubScore("a", 80.0, 0.5, ""),
            SubScore("b", None, 0.5, "", "no data"),
        ],
    )
    assert score.value == pytest.approx(80.0)
    assert score.coverage == pytest.approx(0.5)
    assert score.is_reliable is False


def test_score_with_no_data_is_none_not_zero() -> None:
    score = Score("Test", [SubScore("a", None, 1.0, "", "no data")])
    assert score.value is None
    assert score.coverage == 0.0


def test_coverage_threshold_for_reliability() -> None:
    high = Score("T", [SubScore("a", 50.0, 0.7, ""), SubScore("b", None, 0.3, "")])
    low = Score("T", [SubScore("a", 50.0, 0.5, ""), SubScore("b", None, 0.5, "")])
    assert high.is_reliable is True
    assert low.is_reliable is False


# --------------------------------------------------------------------------
# The firewall — required by the spec, enforced three ways
# --------------------------------------------------------------------------


def test_scoring_module_never_references_firewalled_tables() -> None:
    """Static check: the scoring engine's source must not mention the table.

    This is the enforcement that survives refactors — a future edit that joins
    political_trades into a score fails here.
    """
    source = Path(inspect.getfile(scoring)).read_text()
    tree = ast.parse(source)

    # Collect every string constant and attribute/name identifier in the module.
    referenced: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            referenced.add(node.value)
        elif isinstance(node, ast.Name):
            referenced.add(node.id)
        elif isinstance(node, ast.Attribute):
            referenced.add(node.attr)

    for table in FIREWALLED_TABLES:
        assert table not in referenced, (
            f"scoring.py references the firewalled table {table!r}. Political "
            f"disclosure data must never contribute to a score."
        )


def test_scoring_module_does_not_import_the_political_trade_model() -> None:
    source = Path(inspect.getfile(scoring)).read_text()
    tree = ast.parse(source)
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.ImportFrom, ast.Import)):
            for alias in node.names:
                imported.add(alias.name)
    assert "PoliticalTrade" not in imported


def test_firewalled_session_blocks_queries_on_political_trades(db_session) -> None:
    """Runtime check: even a hand-written query is refused during scoring."""
    from sqlalchemy import text

    from invest.engines.scoring import FirewalledSession, FirewallViolation

    with (
        FirewalledSession(db_session) as session,
        pytest.raises(FirewallViolation, match="firewalled table"),
    ):
        session.execute(text("SELECT count(*) FROM political_trades")).scalar()


def test_firewalled_session_allows_normal_queries(db_session) -> None:
    from sqlalchemy import text

    from invest.engines.scoring import FirewalledSession

    with FirewalledSession(db_session) as session:
        assert session.execute(text("SELECT count(*) FROM price_observations")).scalar() == 0


def test_firewall_is_released_after_scoring(db_session) -> None:
    """The guard must not leak onto the connection for the rest of the session."""
    from sqlalchemy import text

    from invest.engines.scoring import FirewalledSession

    with FirewalledSession(db_session):
        pass
    # Outside the scoring context, reading the table for research is fine.
    assert db_session.execute(text("SELECT count(*) FROM political_trades")).scalar() == 0


# --------------------------------------------------------------------------
# Investment Quality
# --------------------------------------------------------------------------


def strong_company() -> QualityInputs:
    current = FinancialInputs(
        revenue=1000,
        gross_profit=400,
        net_income=100,
        operating_cash_flow=150,
        operating_income=150,
        pretax_income=130,
        tax_expense=30,
        total_assets=1000,
        current_assets=500,
        current_liabilities=250,
        total_liabilities=400,
        equity=600,
        retained_earnings=300,
        long_term_debt=100,
        shares_diluted=1000,
        market_cap=1500,
        receivables=100,
        ppe_net=300,
        depreciation_amortization=50,
        sga_expense=150,
        cash=100,
    )
    prior = FinancialInputs(
        revenue=900,
        gross_profit=315,
        net_income=50,
        operating_cash_flow=60,
        total_assets=1000,
        current_assets=400,
        current_liabilities=250,
        long_term_debt=150,
        shares_diluted=1000,
        receivables=90,
        ppe_net=300,
        depreciation_amortization=50,
        sga_expense=140,
    )
    return QualityInputs(
        piotroski=piotroski_f_score(current, prior),
        altman=altman_z_score(current),
        beneish=beneish_m_score(current, prior),
        revenue_cagr=0.12,
        fcf_cagr=0.10,
        dcf_upside=0.25,
    )


def test_quality_score_is_decomposable() -> None:
    """A score with no visible components is an opinion wearing a number."""
    score = investment_quality_score(strong_company())
    assert score.value is not None
    assert len(score.components) >= 6
    assert all(c.name and c.detail for c in score.components)


def test_strong_company_scores_well() -> None:
    score = investment_quality_score(strong_company())
    assert score.value > 60


def test_empty_inputs_give_no_quality_score() -> None:
    score = investment_quality_score(QualityInputs())
    assert score.value is None
    assert score.coverage == 0.0


def test_bank_gets_altman_excluded_with_a_reason() -> None:
    """Not applicable is different from missing, and the report says which."""
    current = FinancialInputs(
        total_assets=1000, equity=100, revenue=200, operating_income=50, market_cap=500
    )
    inputs = QualityInputs(altman=altman_z_score(current, is_financial=True))
    score = investment_quality_score(inputs)
    altman_component = next(c for c in score.components if c.name == "altman_z_score")
    assert altman_component.value is None
    assert "not applicable" in altman_component.detail.lower()
    assert any("banks" in w for w in score.warnings)


def test_unreliable_piotroski_is_excluded_and_flagged() -> None:
    """A score built from three of nine signals is not comparable to a full
    one, so it is left out rather than blended in.
    """
    thin = piotroski_f_score(
        FinancialInputs(net_income=100, total_assets=1000, operating_cash_flow=150),
        FinancialInputs(),
    )
    score = investment_quality_score(QualityInputs(piotroski=thin))
    component = next(c for c in score.components if c.name == "piotroski_f_score")
    assert component.value is None
    assert any("Piotroski excluded" in w for w in score.warnings)


def test_manipulation_flag_produces_a_warning() -> None:
    current = FinancialInputs(
        revenue=1000, gross_profit=400, receivables=500, total_assets=2000,
        current_assets=800, ppe_net=1000, depreciation_amortization=100,
        sga_expense=200, current_liabilities=300, long_term_debt=500,
        net_income=300, operating_cash_flow=-200,
    )
    prior = FinancialInputs(
        revenue=1000, gross_profit=400, receivables=100, total_assets=2000,
        current_assets=800, ppe_net=1000, depreciation_amortization=100,
        sga_expense=200, current_liabilities=300, long_term_debt=500,
        net_income=100, operating_cash_flow=100,
    )
    score = investment_quality_score(QualityInputs(beneish=beneish_m_score(current, prior)))
    assert any("manipulat" in w.lower() for w in score.warnings)
    assert any("not a conclusion" in w for w in score.warnings)


# --------------------------------------------------------------------------
# Trade Setup
# --------------------------------------------------------------------------


def test_uptrend_scores_higher_than_downtrend() -> None:
    uptrend = trade_setup_score(
        TradeSetupInputs(
            price=110, sma_20=108, sma_50=105, sma_100=102, sma_200=100,
            rsi=55, macd_histogram=1.0, relative_strength=0.10,
            position_52w=0.70, atr_pct=0.015,
        )
    )
    downtrend = trade_setup_score(
        TradeSetupInputs(
            price=90, sma_20=95, sma_50=100, sma_100=105, sma_200=110,
            rsi=35, macd_histogram=-1.0, relative_strength=-0.15,
            position_52w=0.10, atr_pct=0.05,
        )
    )
    assert uptrend.value > downtrend.value


def test_ma_alignment_hand_checked() -> None:
    bullish = trade_setup_score(TradeSetupInputs(price=100, sma_20=99, sma_50=95, sma_200=90))
    component = next(c for c in bullish.components if c.name == "ma_alignment")
    assert component.value == 100.0

    bearish = trade_setup_score(TradeSetupInputs(price=100, sma_20=90, sma_50=95, sma_200=99))
    component = next(c for c in bearish.components if c.name == "ma_alignment")
    assert component.value == 0.0


def test_trend_structure_hand_checked() -> None:
    """Price above 2 of 4 moving averages -> 50."""
    score = trade_setup_score(
        TradeSetupInputs(price=100, sma_20=95, sma_50=98, sma_100=105, sma_200=110)
    )
    component = next(c for c in score.components if c.name == "trend_structure")
    assert component.value == pytest.approx(50.0)


def test_rsi_extremes_are_both_penalised() -> None:
    """The RSI component is a tent, not a ramp: 90 is not 'better' than 55."""
    mid = trade_setup_score(TradeSetupInputs(price=100, rsi=50))
    overbought = trade_setup_score(TradeSetupInputs(price=100, rsi=90))
    oversold = trade_setup_score(TradeSetupInputs(price=100, rsi=10))

    def rsi_value(score):
        return next(c for c in score.components if c.name == "rsi").value

    assert rsi_value(mid) > rsi_value(overbought)
    assert rsi_value(mid) > rsi_value(oversold)


def test_overbought_rsi_warns() -> None:
    score = trade_setup_score(TradeSetupInputs(price=100, rsi=85))
    assert any("overbought" in w for w in score.warnings)


def test_no_insider_data_is_reported_as_unavailable_not_neutral() -> None:
    score = trade_setup_score(TradeSetupInputs(price=100, insider_transaction_count=0))
    component = next(c for c in score.components if c.name == "insider_conviction")
    assert component.value is None
    assert "no Form 4 data" in component.unavailable_reason


def test_insider_buying_scores_above_selling() -> None:
    buying = trade_setup_score(
        TradeSetupInputs(price=100, insider_net_buy_ratio=0.8, insider_transaction_count=5)
    )
    selling = trade_setup_score(
        TradeSetupInputs(price=100, insider_net_buy_ratio=-0.8, insider_transaction_count=5)
    )
    assert buying.value > selling.value


# --------------------------------------------------------------------------
# Confidence
# --------------------------------------------------------------------------


def test_confidence_is_capped_by_missing_premium_data() -> None:
    """The spec's hard requirement: confidence must be MATERIALLY reduced
    whenever premium-dependent inputs are absent — which in V1 is always.
    """
    perfect = confidence_score(
        ConfidenceInputs(
            price_observations=2000,
            price_days_stale=0,
            fundamental_periods=10,
            fundamental_days_stale=90,
            conflict_count=0,
            critical_conflict_count=0,
            sources_agreeing=3,
            sources_total=3,
            quality_coverage=1.0,
            setup_coverage=1.0,
        )
    )
    # Even with flawless free data, the 25% premium weight scores zero.
    assert perfect.value is not None
    assert perfect.value <= 76.0
    premium = next(c for c in perfect.components if c.name == "premium_data_availability")
    assert premium.value == 0.0
    assert premium.weight == 0.25
    assert "PREMIUM-DATA DEPENDENT" in premium.detail


def test_confidence_warns_about_the_free_data_ceiling() -> None:
    score = confidence_score(ConfidenceInputs())
    assert any("free data only" in w for w in score.warnings)


def test_sparse_data_scores_lower_than_rich_data() -> None:
    sparse = confidence_score(
        ConfidenceInputs(price_observations=10, fundamental_periods=1, quality_coverage=0.2)
    )
    rich = confidence_score(
        ConfidenceInputs(
            price_observations=1000,
            fundamental_periods=5,
            quality_coverage=0.9,
            setup_coverage=0.9,
        )
    )
    assert rich.value > sparse.value


def test_single_source_is_not_treated_as_agreement() -> None:
    """'Nothing disagreed' is not 'everything agreed'."""
    single = confidence_score(ConfidenceInputs(sources_total=1, sources_agreeing=1))
    component = next(c for c in single.components if c.name == "source_agreement")
    assert component.value == 40.0
    assert "no cross-check" in component.detail


def test_conflicts_reduce_confidence() -> None:
    clean = confidence_score(ConfidenceInputs(conflict_count=0))
    messy = confidence_score(ConfidenceInputs(conflict_count=15))
    assert clean.value > messy.value


def test_critical_conflicts_cap_the_component_and_warn() -> None:
    score = confidence_score(ConfidenceInputs(conflict_count=1, critical_conflict_count=1))
    component = next(c for c in score.components if c.name == "data_conflicts")
    assert component.value <= 25.0
    assert any("quarantined" in w for w in score.warnings)


def test_stale_prices_warn() -> None:
    score = confidence_score(ConfidenceInputs(price_days_stale=30))
    assert any("stale" in w for w in score.warnings)


def test_unverified_identifiers_warn() -> None:
    score = confidence_score(ConfidenceInputs(unverified_identifiers=True))
    assert any("verified against SEC EDGAR" in w for w in score.warnings)


# --------------------------------------------------------------------------
# ScoreSet
# --------------------------------------------------------------------------


def test_scores_are_kept_separate_not_blended() -> None:
    """A great company at a terrible entry point and a mediocre company at a
    great entry point must not collapse to the same number.
    """
    scores = ScoreSet(
        quality=investment_quality_score(strong_company()),
        setup=trade_setup_score(TradeSetupInputs(price=100, rsi=50)),
        confidence=confidence_score(ConfidenceInputs()),
    )
    payload = scores.as_dict()
    assert "investment_quality" in payload
    assert "trade_setup" in payload
    assert "confidence" in payload
    assert "composite" not in payload
    assert "overall" not in payload


def test_model_version_is_recorded() -> None:
    scores = ScoreSet(
        quality=Score("Q"), setup=Score("S"), confidence=Score("C")
    )
    assert scores.as_dict()["model_version"] == MODEL_VERSION
    assert MODEL_VERSION.startswith("HF-QM-v")


def test_every_component_serialises_with_its_weight() -> None:
    payload = investment_quality_score(strong_company()).as_dict()
    for component in payload["components"]:
        assert "weight" in component
        assert "value" in component
        assert "detail" in component
