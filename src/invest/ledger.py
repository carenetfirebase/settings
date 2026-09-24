"""Read models over the signal ledger: listings, calibration, attribution.

This is where the engine is held to account. Two questions:

* **Calibration.** Does a higher score mean better outcomes? If setups
  scored 80-90 do no better than setups scored 60-70, the score is decoration.
* **Attribution.** Does each gate and veto earn its place? A veto is worth
  keeping only if the trades it blocks do worse than the trades it lets
  through. Every blocked candidate is in the ledger precisely so this can be
  measured instead of assumed.

## Honest statistics

* Results are in R, net of costs, from closed trades only (target, stop or
  time exit). Open trades and never-triggered signals are counted, not scored.
* Groups with fewer than `MIN_CLOSED` closed trades are flagged as too small
  to judge, and nothing is hidden because it is small.
* A difference between groups is reported with its t-statistic, and the bar
  for believing a new rule is t > 3, not 2 (Harvey, Liu & Zhu 2016), because
  many rules are being tried. Standard errors are clustered by week: signals
  in the same week share one market path and are not independent draws.
* `live` and `backfill` are never pooled by default. A backfill is
  point-in-time but scanned over today's universe, so it is survivorship-biased.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import date
from itertools import pairwise

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from invest.db.models import Security, SignalOutcome, SignalRecord
from invest.engines.backtest import MIN_TRADES_FOR_STATISTICS
from invest.engines.outcomes import FINAL_STATUSES

#: Below this many closed trades a group is reported but flagged.
MIN_CLOSED = MIN_TRADES_FOR_STATISTICS
#: Harvey, Liu & Zhu (2016): the bar for a new factor when many are tried.
T_STAT_BAR = 3.0
SCORE_BUCKETS: tuple[tuple[float, float], ...] = (
    (0.0, 60.0),
    (60.0, 70.0),
    (70.0, 80.0),
    (80.0, 90.0),
    (90.0, 100.0001),
)
SCORED_EXITS = frozenset({"target", "stop", "time"})


@dataclass(frozen=True)
class LedgerRow:
    signal_id: int
    ticker: str
    as_of_date: date
    origin: str
    status: str
    fired: bool
    final_score: float | None
    insider_bonus: float
    entry: float
    stop: float
    target: float
    model_version: str
    checks: list[dict]
    reasons: list[str]
    outcome_status: str | None
    evaluated_through: date | None
    trigger_date: date | None
    exit_date: date | None
    r_net: float | None
    r_gross: float | None
    mfe_r: float | None
    mae_r: float | None
    bars_held: int | None
    first_touch: str | None

    @property
    def closed(self) -> bool:
        return self.outcome_status in SCORED_EXITS and self.r_net is not None

    def failed_check(self, name: str) -> bool:
        return any(c.get("name") == name and c.get("passed") is False for c in self.checks)

    def as_dict(self) -> dict:
        out = dict(self.__dict__)
        for key in ("as_of_date", "evaluated_through", "trigger_date", "exit_date"):
            out[key] = out[key].isoformat() if out[key] else None
        out["closed"] = self.closed
        out["outcome_final"] = self.outcome_status in {s.value for s in FINAL_STATUSES}
        return out


def _num(value) -> float | None:
    return None if value is None else float(value)


def load_ledger(
    session: Session,
    *,
    origin: str | None = None,
    fired_only: bool = False,
    ticker: str | None = None,
    limit: int | None = None,
) -> list[LedgerRow]:
    """Signals with their latest outcome, newest first."""
    latest = (
        select(SignalOutcome.signal_id, func.max(SignalOutcome.id).label("max_id"))
        .group_by(SignalOutcome.signal_id)
        .subquery()
    )
    stmt = (
        select(SignalRecord, Security.ticker, SignalOutcome)
        .join(Security, SignalRecord.security_id == Security.id)
        .outerjoin(latest, latest.c.signal_id == SignalRecord.id)
        .outerjoin(SignalOutcome, SignalOutcome.id == latest.c.max_id)
        .order_by(SignalRecord.as_of_date.desc(), SignalRecord.id.desc())
    )
    if origin:
        stmt = stmt.where(SignalRecord.origin == origin)
    if fired_only:
        stmt = stmt.where(SignalRecord.fired.is_(True))
    if ticker:
        stmt = stmt.where(Security.ticker == ticker.upper())
    if limit:
        stmt = stmt.limit(limit)

    rows: list[LedgerRow] = []
    for signal, sym, outcome in session.execute(stmt).all():
        payload = signal.signal_json or {}
        rows.append(
            LedgerRow(
                signal_id=signal.id,
                ticker=sym,
                as_of_date=signal.as_of_date,
                origin=signal.origin,
                status=signal.status,
                fired=signal.fired,
                final_score=_num(signal.final_score),
                insider_bonus=_num(signal.insider_bonus) or 0.0,
                entry=float(signal.entry),
                stop=float(signal.stop),
                target=float(signal.target),
                model_version=signal.model_version,
                checks=list(payload.get("checks", [])),
                reasons=list(payload.get("reasons", [])),
                outcome_status=outcome.status if outcome else None,
                evaluated_through=outcome.evaluated_through if outcome else None,
                trigger_date=outcome.trigger_date if outcome else None,
                exit_date=outcome.exit_date if outcome else None,
                r_net=_num(outcome.r_net) if outcome else None,
                r_gross=_num(outcome.r_gross) if outcome else None,
                mfe_r=_num(outcome.mfe_r) if outcome else None,
                mae_r=_num(outcome.mae_r) if outcome else None,
                bars_held=outcome.bars_held if outcome else None,
                first_touch=outcome.first_touch if outcome else None,
            )
        )
    return rows


# --------------------------------------------------------------------------
# Group statistics
# --------------------------------------------------------------------------


@dataclass
class GroupStats:
    label: str
    signals: int = 0
    triggered: int = 0
    closed: int = 0
    wins: int = 0
    mean_r: float | None = None
    stderr_r: float | None = None
    win_rate: float | None = None
    first_up_rate: float | None = None
    mean_mfe: float | None = None
    mean_mae: float | None = None
    enough: bool = False
    #: Versus the reference group (attribution only).
    diff_vs_reference: float | None = None
    t_vs_reference: float | None = None
    notes: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return dict(self.__dict__)


def _mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def _stderr(values: list[float]) -> float | None:
    n = len(values)
    if n < 2:
        return None
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1)
    return math.sqrt(var / n)


def _week(day: date) -> tuple[int, int]:
    iso = day.isocalendar()
    return iso[0], iso[1]


def clustered_stderr(pairs: list[tuple[tuple[int, int], float]]) -> float | None:
    """Standard error of the mean, clustered by week.

    Signals from the same week ride one market path, so they are not
    independent, and treating them as if they were overstates certainty. (On
    random-walk test data an unclustered t-statistic reached 4 for a rule with
    no real effect.) This is the cluster-robust variance of a mean, with the
    usual G/(G-1) small-sample correction. It needs at least two clusters.
    """
    n = len(pairs)
    clusters: dict[tuple[int, int], list[float]] = {}
    for key, value in pairs:
        clusters.setdefault(key, []).append(value)
    g = len(clusters)
    if n < 2 or g < 2:
        return None
    mean = sum(v for _, v in pairs) / n
    total = sum(sum(v - mean for v in values) ** 2 for values in clusters.values())
    return math.sqrt(g / (g - 1) * total) / n


def group_stats(label: str, rows: list[LedgerRow]) -> GroupStats:
    closed = [r for r in rows if r.closed]
    returns = [r.r_net for r in closed if r.r_net is not None]
    triggered = [r for r in rows if r.trigger_date is not None]
    touched = [r for r in triggered if r.first_touch is not None]
    stats = GroupStats(
        label=label,
        signals=len(rows),
        triggered=len(triggered),
        closed=len(closed),
        wins=sum(1 for v in returns if v > 0),
        mean_r=_mean(returns),
        stderr_r=clustered_stderr(
            [(_week(r.as_of_date), r.r_net) for r in closed if r.r_net is not None]
        ),
        win_rate=(sum(1 for v in returns if v > 0) / len(returns)) if returns else None,
        first_up_rate=(sum(1 for r in touched if r.first_touch == "up") / len(touched))
        if touched
        else None,
        mean_mfe=_mean([r.mfe_r for r in closed if r.mfe_r is not None]),
        mean_mae=_mean([r.mae_r for r in closed if r.mae_r is not None]),
        enough=len(closed) >= MIN_CLOSED,
    )
    if not stats.enough:
        stats.notes.append(
            f"Only {len(closed)} closed trades: too few to judge (need {MIN_CLOSED})."
        )
    return stats


def _compare(group: GroupStats, reference: GroupStats) -> None:
    if group.mean_r is None or reference.mean_r is None:
        return
    group.diff_vs_reference = group.mean_r - reference.mean_r
    if group.stderr_r and reference.stderr_r:
        se = math.sqrt(group.stderr_r**2 + reference.stderr_r**2)
        if se > 0:
            group.t_vs_reference = group.diff_vs_reference / se


@dataclass
class Calibration:
    origin: str | None
    fired_only: bool
    buckets: list[GroupStats]
    overall: GroupStats
    monotonic: bool | None
    note: str

    def as_dict(self) -> dict:
        return {
            "origin": self.origin,
            "fired_only": self.fired_only,
            "buckets": [b.as_dict() for b in self.buckets],
            "overall": self.overall.as_dict(),
            "monotonic": self.monotonic,
            "note": self.note,
            "min_closed": MIN_CLOSED,
        }


def calibration(rows: list[LedgerRow], *, origin: str | None, fired_only: bool) -> Calibration:
    """Outcomes by score bucket. `monotonic` is only claimed when every bucket
    has enough closed trades to compare.
    """
    buckets: list[GroupStats] = []
    for low, high in SCORE_BUCKETS:
        members = [r for r in rows if r.final_score is not None and low <= r.final_score < high]
        label = f"{low:.0f}–{min(high, 100):.0f}"
        buckets.append(group_stats(label, members))

    judged = [b for b in buckets if b.enough and b.mean_r is not None]
    monotonic: bool | None = None
    if len(judged) >= 2 and len(judged) == sum(1 for b in buckets if b.signals):
        means = [b.mean_r for b in judged]
        monotonic = all(a <= b for a, b in pairwise(means))

    note = (
        "A score is calibrated when higher buckets earn more per trade. Until "
        f"each bucket has {MIN_CLOSED} closed trades, treat the score as a ranking, not a probability."
    )
    return Calibration(origin, fired_only, buckets, group_stats("All", rows), monotonic, note)


@dataclass
class Attribution:
    origin: str | None
    reference: GroupStats
    groups: list[GroupStats]
    note: str

    def as_dict(self) -> dict:
        return {
            "origin": self.origin,
            "reference": self.reference.as_dict(),
            "groups": [g.as_dict() for g in self.groups],
            "t_stat_bar": T_STAT_BAR,
            "note": self.note,
        }


def attribution(rows: list[LedgerRow], *, origin: str | None) -> Attribution:
    """Blocked candidates versus fired ones, one gate or veto at a time."""
    fired = [r for r in rows if r.fired]
    reference = group_stats("Fired: every gate passed", fired)
    groups = [
        group_stats("Blocked by the trend gate", [r for r in rows if r.status == "gate_closed"]),
        group_stats(
            "Blocked by the quality veto", [r for r in rows if r.failed_check("quality_veto")]
        ),
        group_stats(
            "Blocked by the earnings veto", [r for r in rows if r.failed_check("earnings_veto")]
        ),
        group_stats("Fired with an insider bonus", [r for r in fired if r.insider_bonus > 0]),
        group_stats("Fired without an insider bonus", [r for r in fired if r.insider_bonus <= 0]),
    ]
    for group in groups:
        _compare(group, reference)
    note = (
        "A gate or veto earns its place if what it blocks does worse than what it lets "
        f"through. Trust a difference only past |t| > {T_STAT_BAR:.0f} (Harvey, Liu & Zhu 2016). "
        "Standard errors are clustered by week, because same-week signals are not independent."
    )
    return Attribution(origin, reference, groups, note)
