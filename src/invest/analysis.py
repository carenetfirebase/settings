"""Orchestration: read point-in-time data, run the engines, write a snapshot.

This is the only module that knows how to turn a ticker into a full research
run. The engines stay ignorant of the database; the repository stays ignorant
of the models; this module joins them.

Everything it reads goes through `repository`, so the point-in-time and
quarantine guarantees hold automatically.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag
from invest.db.models import DataConflict, Fundamental, PriceObservation, ResearchSnapshot
from invest.engines import quant
from invest.engines.fundamentals import (
    FinancialInputs,
    altman_z_score,
    beneish_m_score,
    dupont,
    piotroski_f_score,
    roic_vs_wacc,
)
from invest.engines.scoring import (
    MODEL_VERSION,
    ConfidenceInputs,
    FirewalledSession,
    QualityInputs,
    ScoreSet,
    TradeSetupInputs,
    confidence_score,
    investment_quality_score,
    trade_setup_score,
)
from invest.engines.valuation import (
    DcfAssumptions,
    ReverseDcfResult,
    ScenarioSet,
    reverse_dcf,
    scenario_dcf,
)
from invest.reports.research_report import render_report
from invest.repository import (
    FundamentalPoint,
    get_close_series,
    get_fundamental_series,
    get_price_frame,
    latest_price,
    shares_outstanding,
)
from invest.security_master import ResolvedSecurity, resolve

#: Metrics pulled for the fundamental models.
REQUIRED_METRICS = (
    "Revenues",
    "GrossProfit",
    "OperatingIncomeLoss",
    "NetIncomeLoss",
    "InterestExpense",
    "IncomeTaxExpenseBenefit",
    "IncomeLossBeforeIncomeTaxes",
    "DepreciationAndAmortization",
    "SellingGeneralAndAdministrativeExpense",
    "Assets",
    "AssetsCurrent",
    "Liabilities",
    "LiabilitiesCurrent",
    "StockholdersEquity",
    "CashAndCashEquivalents",
    "InventoryNet",
    "AccountsReceivableNetCurrent",
    "PropertyPlantAndEquipmentNet",
    "LongTermDebtNoncurrent",
    "LongTermDebtCurrent",
    "RetainedEarningsAccumulatedDeficit",
    "NetCashProvidedByOperatingActivities",
    "CapitalExpenditures",
    "WeightedAverageDilutedShares",
)

DEFAULT_DISCOUNT_RATE = 0.09
DEFAULT_TERMINAL_GROWTH = 0.025


def _point_for_year(points: list[FundamentalPoint], offset: int) -> FundamentalPoint | None:
    """`offset=0` is the latest annual period, `offset=1` the one before."""
    index = len(points) - 1 - offset
    return points[index] if 0 <= index < len(points) else None


def _value(points: list[FundamentalPoint], offset: int) -> float | None:
    point = _point_for_year(points, offset)
    return point.value if point else None


def build_financial_inputs(
    metrics: dict[str, list[FundamentalPoint]],
    *,
    offset: int = 0,
    market_cap: float | None = None,
) -> FinancialInputs:
    """Assemble one year's line items. Anything absent stays None."""

    def get(name: str) -> float | None:
        return _value(metrics.get(name, []), offset)

    return FinancialInputs(
        revenue=get("Revenues"),
        gross_profit=get("GrossProfit"),
        operating_income=get("OperatingIncomeLoss"),
        net_income=get("NetIncomeLoss"),
        interest_expense=get("InterestExpense"),
        tax_expense=get("IncomeTaxExpenseBenefit"),
        pretax_income=get("IncomeLossBeforeIncomeTaxes"),
        depreciation_amortization=get("DepreciationAndAmortization"),
        sga_expense=get("SellingGeneralAndAdministrativeExpense"),
        total_assets=get("Assets"),
        current_assets=get("AssetsCurrent"),
        total_liabilities=get("Liabilities"),
        current_liabilities=get("LiabilitiesCurrent"),
        equity=get("StockholdersEquity"),
        cash=get("CashAndCashEquivalents"),
        inventory=get("InventoryNet"),
        receivables=get("AccountsReceivableNetCurrent"),
        ppe_net=get("PropertyPlantAndEquipmentNet"),
        long_term_debt=get("LongTermDebtNoncurrent"),
        current_debt=get("LongTermDebtCurrent"),
        retained_earnings=get("RetainedEarningsAccumulatedDeficit"),
        operating_cash_flow=get("NetCashProvidedByOperatingActivities"),
        capex=get("CapitalExpenditures"),
        shares_diluted=get("WeightedAverageDilutedShares"),
        market_cap=market_cap,
    )


@dataclass
class AnalysisResult:
    security: ResolvedSecurity
    as_of: date
    scores: ScoreSet
    report_text: str
    inputs_json: dict
    components_json: dict
    snapshot_id: int | None = None


def analyze(
    session: Session,
    ticker: str,
    *,
    as_of: date | None = None,
    benchmark_security_id: int | None = None,
    discount_rate: float = DEFAULT_DISCOUNT_RATE,
    risk_free_rate: float | None = None,
) -> AnalysisResult:
    """Run the full research pipeline for one ticker.

    Scoring runs inside a FirewalledSession, so any attempt to read political
    trade data raises rather than silently contaminating a score.
    """
    security = resolve(session, ticker)
    as_of = as_of or date.today()

    # ---- Prices -------------------------------------------------------
    prices = get_close_series(session, security.security_id, as_of=as_of)
    price_frame = get_price_frame(session, security.security_id, as_of=as_of)
    last = latest_price(session, security.security_id, as_of=as_of)
    current_price = last[1] if last else None
    price_days_stale = (as_of - last[0]).days if last else None

    # ---- Fundamentals -------------------------------------------------
    metrics = {
        name: get_fundamental_series(
            session, security.entity_id, name, as_of=as_of, fiscal_period="FY"
        )
        for name in REQUIRED_METRICS
    }
    share_count = shares_outstanding(session, security.entity_id, as_of=as_of)
    market_cap = current_price * share_count if (current_price and share_count) else None

    current_year = build_financial_inputs(metrics, offset=0, market_cap=market_cap)
    prior_year = build_financial_inputs(metrics, offset=1, market_cap=market_cap)

    revenue_points = metrics.get("Revenues", [])
    fundamental_periods = len(revenue_points)
    fundamental_days_stale = (
        (as_of - revenue_points[-1].filed_date).days if revenue_points else None
    )

    # ---- Fundamental models -------------------------------------------
    piotroski = piotroski_f_score(current_year, prior_year)
    altman = altman_z_score(current_year, is_financial=security.is_financial)
    beneish = beneish_m_score(current_year, prior_year)
    dupont_result = dupont(current_year)

    beta_estimate = None
    if benchmark_security_id is not None:
        benchmark = get_close_series(session, benchmark_security_id, as_of=as_of)
        beta_result = quant.beta(quant.simple_returns(prices), quant.simple_returns(benchmark))
        beta_estimate = beta_result.beta if beta_result else None

    roic = roic_vs_wacc(
        current_year, beta=beta_estimate, risk_free_rate=risk_free_rate
    )

    # ---- Growth --------------------------------------------------------
    revenue_values = [p.value for p in revenue_points]
    revenue_cagr = None
    if len(revenue_values) >= 2 and revenue_values[0] and revenue_values[-1]:
        revenue_cagr = quant.cagr(
            revenue_values[0], revenue_values[-1], len(revenue_values) - 1
        )

    fcf_history: list[float] = []
    for offset in range(min(5, fundamental_periods)):
        year = build_financial_inputs(metrics, offset=offset)
        if year.free_cash_flow is not None:
            fcf_history.append(year.free_cash_flow)
    fcf_history.reverse()  # oldest first
    fcf_cagr = None
    if len(fcf_history) >= 2 and fcf_history[0] > 0 and fcf_history[-1] > 0:
        fcf_cagr = quant.cagr(fcf_history[0], fcf_history[-1], len(fcf_history) - 1)

    # ---- Valuation -----------------------------------------------------
    base_fcf = current_year.free_cash_flow
    net_debt = None
    if current_year.total_debt is not None or current_year.cash is not None:
        net_debt = (current_year.total_debt or 0.0) - (current_year.cash or 0.0)

    scenarios: ScenarioSet | None = None
    reverse: ReverseDcfResult | None = None
    dcf_upside = None
    implied_growth_gap = None

    if base_fcf is not None and base_fcf > 0:
        growth_assumption = fcf_cagr if fcf_cagr is not None else 0.05
        # Cap the extrapolated growth: projecting a recent 60% CAGR for a
        # decade is how DCFs produce absurd numbers.
        growth_assumption = max(-0.10, min(0.15, growth_assumption))
        try:
            base_assumptions = DcfAssumptions(
                growth_rate=growth_assumption,
                terminal_growth_rate=DEFAULT_TERMINAL_GROWTH,
                discount_rate=discount_rate,
            )
        except ValueError:
            base_assumptions = None

        if base_assumptions is not None:
            scenarios = scenario_dcf(
                base_free_cash_flow=base_fcf,
                base_assumptions=base_assumptions,
                shares_outstanding=share_count,
                net_debt=net_debt,
                current_price=current_price,
            )
            dcf_upside = scenarios.base.upside

            reverse = reverse_dcf(
                market_price=current_price,
                base_free_cash_flow=base_fcf,
                shares_outstanding=share_count,
                discount_rate=discount_rate,
                terminal_growth_rate=DEFAULT_TERMINAL_GROWTH,
                net_debt=net_debt,
            )
            if reverse.implied_growth_rate is not None and fcf_cagr is not None:
                implied_growth_gap = fcf_cagr - reverse.implied_growth_rate

    # ---- Technicals ----------------------------------------------------
    def _last(series) -> float | None:
        cleaned = series.dropna()
        return float(cleaned.iloc[-1]) if len(cleaned) else None

    setup_inputs = TradeSetupInputs(price=current_price)
    if not prices.empty:
        setup_inputs = TradeSetupInputs(
            price=current_price,
            sma_20=_last(quant.sma(prices, 20)),
            sma_50=_last(quant.sma(prices, 50)),
            sma_100=_last(quant.sma(prices, 100)),
            sma_200=_last(quant.sma(prices, 200)),
            rsi=_last(quant.rsi(prices)),
            macd_histogram=_last(quant.macd(prices).histogram),
            percent_b=None,
            position_52w=quant.position_in_52_week_range(prices),
        )
        if not price_frame.empty and {"high", "low"} <= set(price_frame.columns):
            atr_series = quant.atr(
                price_frame["high"], price_frame["low"], price_frame["close"]
            )
            atr_value = _last(atr_series)
            if atr_value is not None and current_price:
                setup_inputs.atr_pct = atr_value / current_price

        if benchmark_security_id is not None:
            benchmark = get_close_series(session, benchmark_security_id, as_of=as_of)
            setup_inputs.relative_strength = quant.relative_strength(prices, benchmark)

    # ---- Data quality --------------------------------------------------
    conflict_count = (
        session.scalar(
            select(func.count())
            .select_from(DataConflict)
            .where(DataConflict.security_id == security.security_id)
        )
        or 0
    )
    critical_conflicts = (
        session.scalar(
            select(func.count())
            .select_from(DataConflict)
            .where(DataConflict.security_id == security.security_id)
            .where(DataConflict.severity == "critical")
        )
        or 0
    )
    sources = (
        session.scalars(
            select(PriceObservation.source)
            .where(PriceObservation.security_id == security.security_id)
            .distinct()
        ).all()
        or []
    )
    price_observation_count = (
        session.scalar(
            select(func.count())
            .select_from(PriceObservation)
            .where(PriceObservation.security_id == security.security_id)
            .where(PriceObservation.data_quality_flag != DataQualityFlag.QUARANTINED)
        )
        or 0
    )
    unverified = (
        session.scalar(
            select(func.count())
            .select_from(Fundamental)
            .where(Fundamental.entity_id == security.entity_id)
        )
        or 0
    ) == 0

    # ---- Scores (firewalled) -------------------------------------------
    quality_inputs = QualityInputs(
        piotroski=piotroski,
        altman=altman,
        beneish=beneish,
        dupont=dupont_result,
        roic=roic,
        revenue_cagr=revenue_cagr,
        fcf_cagr=fcf_cagr,
        dcf_upside=dcf_upside,
        implied_growth_gap=implied_growth_gap,
    )

    with FirewalledSession(session):
        quality = investment_quality_score(quality_inputs)
        setup = trade_setup_score(setup_inputs)
        confidence = confidence_score(
            ConfidenceInputs(
                price_observations=price_observation_count,
                price_days_stale=price_days_stale,
                fundamental_periods=fundamental_periods,
                fundamental_days_stale=fundamental_days_stale,
                conflict_count=conflict_count,
                critical_conflict_count=critical_conflicts,
                sources_agreeing=max(0, len(sources) - (1 if critical_conflicts else 0)),
                sources_total=len(sources),
                quality_coverage=quality.coverage,
                setup_coverage=setup.coverage,
                unverified_identifiers=unverified,
            )
        )

    scores = ScoreSet(
        quality=quality, setup=setup, confidence=confidence, as_of=as_of
    )

    report_text = render_report(
        ticker=security.ticker,
        company_name=security.name,
        cik=security.cik,
        as_of=as_of,
        price=current_price,
        scores=scores,
        piotroski=piotroski,
        altman=altman,
        beneish=beneish,
        dupont=dupont_result,
        roic=roic,
        scenarios=scenarios,
        reverse=reverse,
        historical_growth=fcf_cagr,
    )

    # Exactly what fed the scores, for reproducibility.
    inputs_json = {
        "as_of": as_of.isoformat(),
        "price": current_price,
        "price_observations": price_observation_count,
        "price_sources": list(sources),
        "market_cap": market_cap,
        "shares_outstanding": share_count,
        "fundamental_periods": fundamental_periods,
        "metrics_available": {
            name: len(points) for name, points in metrics.items() if points
        },
        "metrics_missing": [name for name, points in metrics.items() if not points],
        "revenue_cagr": revenue_cagr,
        "fcf_cagr": fcf_cagr,
        "base_free_cash_flow": base_fcf,
        "net_debt": net_debt,
        "discount_rate": discount_rate,
        "beta": beta_estimate,
        "conflict_count": conflict_count,
        "critical_conflict_count": critical_conflicts,
    }

    components_json = {
        "scores": scores.as_dict(),
        "piotroski": piotroski.as_dict(),
        "altman": altman.as_dict(),
        "beneish": beneish.as_dict(),
        "dupont": dupont_result.as_dict(),
        "roic": roic.as_dict(),
        "valuation": scenarios.as_dict() if scenarios else None,
        "reverse_dcf": reverse.as_dict() if reverse else None,
    }

    return AnalysisResult(
        security=security,
        as_of=as_of,
        scores=scores,
        report_text=report_text,
        inputs_json=inputs_json,
        components_json=components_json,
    )


def save_snapshot(session: Session, result: AnalysisResult) -> ResearchSnapshot:
    """Persist an immutable record of the run.

    The row can never be updated (append-only trigger), so re-running on the
    same day creates a second snapshot rather than mutating the first. That is
    intentional: the history of what we thought, and when, is the point.
    """
    snapshot = ResearchSnapshot(
        entity_id=result.security.entity_id,
        security_id=result.security.security_id,
        snapshot_date=date.today(),
        as_of_date=result.as_of,
        model_version=MODEL_VERSION,
        investment_quality_score=result.scores.quality.value,
        trade_setup_score=result.scores.setup.value,
        confidence_score=result.scores.confidence.value,
        components_json=result.components_json,
        inputs_json=result.inputs_json,
        warnings_json={"warnings": result.scores.all_warnings},
        report_text=result.report_text,
    )
    session.add(snapshot)
    session.flush()
    result.snapshot_id = snapshot.id
    return snapshot
