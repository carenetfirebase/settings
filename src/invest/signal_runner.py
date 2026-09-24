"""Run the signal engine against the database: scan, record, evaluate, backfill.

The engine (`engines/signals.py`) is pure. This module feeds it point-in-time
data and writes what it finds to the append-only ledger.

## Point-in-time, loaded once

A backfill scans hundreds of days. Rather than re-query everything per day,
`ScanData` loads each security's history once and slices it in memory by the
date each fact became public:

* prices by `obs_date`,
* insider trades by `filed_date` (the engine re-checks this),
* earnings announcements by the 8-K `filed_date`,
* fundamentals through the repository's own restatement-aware query, cached
  per filing state so it runs once per new filing rather than once per day.

## Live versus backfill

A signal recorded on the day it was generated is `live`. Anything generated
for a past date is `backfill`: it is point-in-time, but it is scanned over
today's universe, so it carries survivorship bias and is never presented as a
track record. The Lab keeps the two apart.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass, field
from datetime import date, timedelta

import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from invest.analysis import REQUIRED_METRICS, build_financial_inputs
from invest.db.enums import EntityType
from invest.db.models import Entity, Filing, Fundamental, Security, SignalOutcome, SignalRecord
from invest.engines.costs import DEFAULT_COSTS, CostModel
from invest.engines.fundamentals import (
    BeneishResult,
    PiotroskiResult,
    beneish_m_score,
    piotroski_f_score,
)
from invest.engines.outcomes import FINAL_STATUSES, Outcome, evaluate_outcome
from invest.engines.signals import (
    MODEL_VERSION,
    Check,
    MarketContext,
    SignalStatus,
    SymbolInputs,
    SymbolSignal,
    VolatilityScale,
    evaluate_symbol,
    momentum_12_1,
    percentile_ranks,
    trend_gate,
    volatility_scale,
)
from invest.providers.base import InsiderTransactionRecord
from invest.repository import get_fundamental_series, get_insider_transactions, get_price_frame
from invest.universe import BENCHMARK_FUND, SECTOR_FUND_BY_SECTOR, SECTOR_FUND_TICKERS

SETUP = "pullback_in_uptrend"
EARNINGS_ITEM = "2.02"
#: The ledger holds long-only pullback cards; a signal for any other setup
#: would need its own evaluator.
LEDGER_SETUPS = (SETUP,)


# --------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------


@dataclass
class SecurityData:
    security_id: int
    entity_id: int
    ticker: str
    name: str
    sector: str | None
    is_fund: bool
    frame: pd.DataFrame
    fundamental_filed_dates: list[date] = field(default_factory=list)
    earnings_dates: list[date] = field(default_factory=list)
    insider_records: list[InsiderTransactionRecord] = field(default_factory=list)

    def frame_as_of(self, as_of: date) -> pd.DataFrame:
        """Bars dated on or before `as_of`. The index is sorted, so this is a
        binary search rather than a scan: a backfill calls it thousands of times.
        """
        if self.frame.empty:
            return self.frame
        return self.frame.iloc[: bisect_right(self._dates, as_of)]

    @property
    def _dates(self) -> tuple[date, ...]:
        cached = self.__dict__.get("_dates_cache")
        if cached is None or len(cached) != len(self.frame):
            cached = tuple(self.frame.index)
            self.__dict__["_dates_cache"] = cached
        return cached

    def last_filing_state(self, as_of: date) -> date | None:
        visible = [d for d in self.fundamental_filed_dates if d <= as_of]
        return visible[-1] if visible else None


class ScanData:
    """Everything a scan needs through `through`, loaded once."""

    def __init__(self, session: Session, *, through: date, include_stocks: bool = True) -> None:
        self.session = session
        self.through = through
        self._quality_cache: dict[tuple[int, date], tuple[PiotroskiResult, BeneishResult]] = {}

        rows = session.execute(
            select(Security, Entity)
            .join(Entity, Security.entity_id == Entity.id)
            .order_by(Security.ticker)
        ).all()
        self.stocks: list[SecurityData] = []
        self.funds: dict[str, SecurityData] = {}
        for security, entity in rows:
            is_fund = entity.entity_type == EntityType.FUND
            if not is_fund and (entity.entity_type != EntityType.COMPANY or not include_stocks):
                continue
            data = SecurityData(
                security_id=security.id,
                entity_id=entity.id,
                ticker=security.ticker,
                name=entity.name,
                sector=entity.sector,
                is_fund=is_fund,
                frame=get_price_frame(session, security.id, as_of=through),
            )
            if is_fund:
                self.funds[security.ticker] = data
            else:
                self._load_company_facts(data)
                self.stocks.append(data)

    def _load_company_facts(self, data: SecurityData) -> None:
        session = self.session
        data.fundamental_filed_dates = sorted(
            session.scalars(
                select(Fundamental.filed_date)
                .where(Fundamental.entity_id == data.entity_id)
                .where(Fundamental.filed_date <= self.through)
                .distinct()
            ).all()
        )
        data.earnings_dates = sorted(
            session.scalars(
                select(Filing.filed_date)
                .where(Filing.entity_id == data.entity_id)
                .where(Filing.form_type.in_(("8-K", "8-K/A")))
                .where(Filing.items.contains(EARNINGS_ITEM))
                .where(Filing.filed_date <= self.through)
            ).all()
        )
        span = (self.through - date(1990, 1, 1)).days
        data.insider_records = get_insider_transactions(
            session, data.entity_id, as_of=self.through, lookback_days=span
        )

    @property
    def benchmark(self) -> SecurityData | None:
        return self.funds.get(BENCHMARK_FUND)

    def trading_days(self, start: date, end: date) -> list[date]:
        """The benchmark's bar dates in [start, end]: the days a scan can run."""
        bench = self.benchmark
        if bench is None or bench.frame.empty:
            return []
        return [d for d in bench.frame.index if start <= d <= end]

    def quality(
        self, data: SecurityData, as_of: date
    ) -> tuple[PiotroskiResult | None, BeneishResult | None]:
        """F-score and M-score as filed on or before `as_of`, via the
        repository's restatement-aware query, cached per filing state.
        """
        state = data.last_filing_state(as_of)
        if state is None:
            return None, None
        key = (data.entity_id, state)
        if key not in self._quality_cache:
            metrics = {
                name: get_fundamental_series(
                    self.session, data.entity_id, name, as_of=state, fiscal_period="FY"
                )
                for name in REQUIRED_METRICS
            }
            current = build_financial_inputs(metrics, offset=0)
            prior = build_financial_inputs(metrics, offset=1)
            self._quality_cache[key] = (
                piotroski_f_score(current, prior),
                beneish_m_score(current, prior),
            )
        return self._quality_cache[key]


# --------------------------------------------------------------------------
# Scanning
# --------------------------------------------------------------------------


def _period_return(closes: pd.Series, days: int) -> float | None:
    clean = closes.dropna()
    if len(clean) <= days:
        return None
    return float(clean.iloc[-1]) / float(clean.iloc[-1 - days]) - 1


@dataclass
class SectorRow:
    ticker: str
    sector: str | None
    momentum_12_1: float | None
    relative_12_1: float | None
    return_1m: float | None
    return_3m: float | None
    relative_1m: float | None
    relative_3m: float | None
    percentile: float | None

    def as_dict(self) -> dict:
        return dict(self.__dict__)


@dataclass
class ScanResult:
    as_of: date
    gate: Check
    volatility: VolatilityScale
    signals: list[SymbolSignal]
    sectors: list[SectorRow]
    security_ids: dict[str, int]
    names: dict[str, str]
    sectors_by_ticker: dict[str, str | None]
    equity: float | None
    warnings: list[str] = field(default_factory=list)
    model_version: str = MODEL_VERSION

    @property
    def cards(self) -> list[SymbolSignal]:
        return sorted(
            (s for s in self.signals if s.fired),
            key=lambda s: -(s.final_score or 0.0),
        )

    @property
    def candidates(self) -> list[SymbolSignal]:
        return [s for s in self.signals if s.is_candidate]

    def counts(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for signal in self.signals:
            out[signal.status.value] = out.get(signal.status.value, 0) + 1
        return out

    def as_dict(self) -> dict:
        order = {status: i for i, status in enumerate(reversed(list(SignalStatus)))}
        ranked = sorted(
            self.signals,
            key=lambda s: (order[s.status], -(s.final_score or 0.0), s.ticker),
        )
        return {
            "as_of": self.as_of.isoformat(),
            "model_version": self.model_version,
            "gate": self.gate.as_dict(),
            "volatility": {
                "multiplier": self.volatility.multiplier,
                "detail": self.volatility.detail,
                "short_vol": self.volatility.short_vol,
                "long_vol": self.volatility.long_vol,
            },
            "equity": self.equity,
            "warnings": self.warnings,
            "counts": self.counts(),
            "sectors": [r.as_dict() for r in self.sectors],
            "signals": [
                {
                    **s.as_dict(),
                    "name": self.names.get(s.ticker),
                    "sector": self.sectors_by_ticker.get(s.ticker),
                }
                for s in ranked
            ],
        }


def scan(
    session: Session,
    *,
    as_of: date | None = None,
    equity: float | None = None,
    data: ScanData | None = None,
) -> ScanResult:
    """Run the engine over every stock in the universe as of `as_of`."""
    as_of = as_of or date.today()
    data = data or ScanData(session, through=as_of)
    warnings: list[str] = []

    bench = data.benchmark
    bench_closes = (
        bench.frame_as_of(as_of)["close"]
        if bench is not None and not bench.frame.empty
        else pd.Series(dtype=float)
    )
    if bench is None:
        warnings.append(f"{BENCHMARK_FUND} is not in the universe: run `invest universe seed`.")
    elif bench_closes.empty:
        warnings.append(
            f"No {BENCHMARK_FUND} prices stored: run `invest ingest prices {BENCHMARK_FUND}`."
        )
    gate = trend_gate(bench_closes, as_of)
    vol = volatility_scale(bench_closes)
    market = MarketContext(as_of=as_of, gate=gate, volatility=vol, equity=equity)

    # ---- sector funds ------------------------------------------------------
    bench_mom = momentum_12_1(bench_closes)
    bench_1m = _period_return(bench_closes, 21)
    bench_3m = _period_return(bench_closes, 63)
    fund_momentum: dict[str, float | None] = {}
    fund_frames: dict[str, pd.Series] = {}
    for ticker in SECTOR_FUND_TICKERS:
        fund = data.funds.get(ticker)
        closes = (
            fund.frame_as_of(as_of)["close"]
            if fund is not None and not fund.frame.empty
            else pd.Series(dtype=float)
        )
        fund_frames[ticker] = closes
        fund_momentum[ticker] = momentum_12_1(closes)
    fund_pct = percentile_ranks(fund_momentum)

    def rel(value: float | None, base: float | None) -> float | None:
        return None if value is None or base is None else value - base

    sectors = [
        SectorRow(
            ticker=t,
            sector=(data.funds[t].sector if t in data.funds else None),
            momentum_12_1=fund_momentum[t],
            relative_12_1=rel(fund_momentum[t], bench_mom),
            return_1m=_period_return(fund_frames[t], 21),
            return_3m=_period_return(fund_frames[t], 63),
            relative_1m=rel(_period_return(fund_frames[t], 21), bench_1m),
            relative_3m=rel(_period_return(fund_frames[t], 63), bench_3m),
            percentile=fund_pct[t],
        )
        for t in SECTOR_FUND_TICKERS
    ]
    sectors.sort(key=lambda r: (r.relative_12_1 is None, -(r.relative_12_1 or 0.0)))
    if all(r.momentum_12_1 is None for r in sectors):
        warnings.append("No sector fund history: sector relative strength is unavailable.")

    # ---- stocks ------------------------------------------------------------
    frames = {s.ticker: s.frame_as_of(as_of) for s in data.stocks}
    stock_momentum = {
        t: momentum_12_1(f["close"]) if not f.empty else None for t, f in frames.items()
    }
    stock_pct = percentile_ranks(stock_momentum)

    results: list[SymbolSignal] = []
    for stock in data.stocks:
        piotroski, beneish = data.quality(stock, as_of)
        sector_fund = SECTOR_FUND_BY_SECTOR.get(stock.sector or "")
        inputs = SymbolInputs(
            ticker=stock.ticker,
            frame=frames[stock.ticker],
            sector=stock.sector,
            sector_fund=sector_fund,
            stock_momentum_percentile=stock_pct.get(stock.ticker),
            sector_momentum_percentile=fund_pct.get(sector_fund) if sector_fund else None,
            piotroski=piotroski,
            beneish=beneish,
            earnings_dates=[d for d in stock.earnings_dates if d <= as_of],
            insider_records=[r for r in stock.insider_records if r.filed_date <= as_of],
        )
        results.append(evaluate_symbol(inputs, market))

    return ScanResult(
        as_of=as_of,
        gate=gate,
        volatility=vol,
        signals=results,
        sectors=sectors,
        security_ids={s.ticker: s.security_id for s in data.stocks},
        names={s.ticker: s.name for s in data.stocks},
        sectors_by_ticker={s.ticker: s.sector for s in data.stocks},
        equity=equity,
        warnings=warnings,
    )


def market_state(session: Session, *, as_of: date | None = None) -> ScanResult:
    """The trend gate, volatility scale and sector table, without scanning
    stocks: what the Command Center and Sectors page need, cheaply.
    """
    as_of = as_of or date.today()
    data = ScanData(session, through=as_of, include_stocks=False)
    return scan(session, as_of=as_of, data=data)


# --------------------------------------------------------------------------
# Recording
# --------------------------------------------------------------------------


@dataclass
class RecordReport:
    written: int = 0
    already_recorded: int = 0


def record_signals(session: Session, result: ScanResult, *, origin: str) -> RecordReport:
    """Append every candidate (fired or not) to the ledger. Idempotent: a
    signal already recorded for that security, day, model and setup is skipped.
    """
    if origin not in ("live", "backfill"):
        raise ValueError("origin must be 'live' or 'backfill'")
    report = RecordReport()
    for signal in result.candidates:
        levels = signal.levels
        assert levels is not None  # guaranteed by is_candidate
        security_id = result.security_ids[signal.ticker]
        exists = session.scalar(
            select(SignalRecord.id).where(
                SignalRecord.security_id == security_id,
                SignalRecord.as_of_date == result.as_of,
                SignalRecord.model_version == signal.model_version,
                SignalRecord.setup == SETUP,
            )
        )
        if exists is not None:
            report.already_recorded += 1
            continue
        session.add(
            SignalRecord(
                security_id=security_id,
                as_of_date=result.as_of,
                model_version=signal.model_version,
                setup=SETUP,
                origin=origin,
                status=signal.status.value,
                fired=signal.fired,
                base_score=signal.base_score,
                final_score=signal.final_score,
                insider_bonus=signal.insider.bonus if signal.insider else 0.0,
                coverage=signal.score.coverage,
                entry=levels.entry,
                stop=levels.stop,
                target=levels.target,
                atr=levels.atr,
                risk_fraction=signal.sizing.risk_fraction if signal.sizing else None,
                vol_multiplier=result.volatility.multiplier,
                signal_json=signal.as_dict(),
            )
        )
        report.written += 1
    session.flush()
    return report


# --------------------------------------------------------------------------
# Evaluating outcomes
# --------------------------------------------------------------------------


def latest_outcomes(session: Session) -> dict[int, SignalOutcome]:
    """The current (latest) outcome row for every signal that has one."""
    latest = (
        select(SignalOutcome.signal_id, func.max(SignalOutcome.id).label("max_id"))
        .group_by(SignalOutcome.signal_id)
        .subquery()
    )
    rows = session.scalars(
        select(SignalOutcome).join(latest, SignalOutcome.id == latest.c.max_id)
    ).all()
    return {row.signal_id: row for row in rows}


@dataclass
class EvaluationReport:
    checked: int = 0
    appended: int = 0
    final: int = 0


def _outcome_row(signal_id: int, outcome: Outcome, costs: CostModel) -> SignalOutcome:
    return SignalOutcome(
        signal_id=signal_id,
        evaluated_through=outcome.evaluated_through,
        status=outcome.status.value,
        trigger_date=outcome.trigger_date,
        entry_fill=outcome.entry_fill,
        exit_date=outcome.exit_date,
        exit_fill=outcome.exit_fill,
        bars_held=outcome.bars_held,
        r_gross=outcome.r_gross,
        cost_r=outcome.cost_r,
        r_net=outcome.r_net,
        mfe_r=outcome.mfe_r,
        mae_r=outcome.mae_r,
        first_touch=outcome.first_touch,
        cost_model_json=costs.as_dict(),
    )


def evaluate_ledger(
    session: Session, *, through: date | None = None, costs: CostModel = DEFAULT_COSTS
) -> EvaluationReport:
    """Re-score every signal whose outcome is not final yet. A row is appended
    only when the outcome changed, so re-running is cheap and idempotent.
    """
    report = EvaluationReport()
    current = latest_outcomes(session)
    signals = session.scalars(select(SignalRecord).order_by(SignalRecord.id)).all()
    for signal in signals:
        previous = current.get(signal.id)
        if previous is not None and previous.status in FINAL_STATUSES:
            report.final += 1
            continue
        report.checked += 1
        bars = get_price_frame(
            session, signal.security_id, start=signal.as_of_date + timedelta(days=1), as_of=through
        )
        outcome = evaluate_outcome(
            entry=float(signal.entry),
            stop=float(signal.stop),
            target=float(signal.target),
            bars_after=bars,
            costs=costs,
        )
        unchanged = previous is not None and (
            previous.status == outcome.status.value
            and previous.evaluated_through == outcome.evaluated_through
        )
        if unchanged:
            continue
        session.add(_outcome_row(signal.id, outcome, costs))
        report.appended += 1
        if outcome.is_final:
            report.final += 1
    session.flush()
    return report


# --------------------------------------------------------------------------
# Backfill
# --------------------------------------------------------------------------


@dataclass
class BackfillReport:
    days: int = 0
    candidates: int = 0
    fired: int = 0
    written: int = 0


def backfill(
    session: Session,
    *,
    start: date,
    end: date,
    equity: float | None = None,
    every: int = 1,
) -> BackfillReport:
    """Scan every `every`-th trading day in [start, end] and record candidates
    as `backfill`. Each day sees only what was public that day.
    """
    if every < 1:
        raise ValueError("every must be >= 1")
    data = ScanData(session, through=end)
    report = BackfillReport()
    for day in data.trading_days(start, end)[::every]:
        result = scan(session, as_of=day, equity=equity, data=data)
        recorded = record_signals(session, result, origin="backfill")
        report.days += 1
        report.candidates += len(result.candidates)
        report.fired += len(result.cards)
        report.written += recorded.written
    return report
