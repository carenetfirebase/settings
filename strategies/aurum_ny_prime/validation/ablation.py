"""Ablation and parameter-stability analysis (S70, S71, S72).

Ablation asks the only question that keeps a filter in a strategy: **what
happens if I remove it?** Each row of the table is a separate Pine run with a
different ablation preset, exported to its own CSV. This module lines the runs
up and reports the deltas against the baseline.

The verdict column is deliberately conservative. A component that improves
expectancy by less than the noise in the estimate has not earned its place, and
"it looked better" is how strategies acquire twelve filters and no edge.
"""

from __future__ import annotations

from dataclasses import dataclass

from .montecarlo import FtmoRules, group_by_day, run_monte_carlo
from .stats import Summary, bootstrap_expectancy, summarize
from .trades import Trade

#: The ladder from S71. Each step adds one component to the one before it.
ABLATION_ORDER = (
    "A · ORB only",
    "B · + VWAP",
    "C · + Asia/London",
    "D · + pivots",
    "E · + third touch",
    "F · + DXY",
    "G · + GC",
    "H · + rates",
    "I · + VIX",
    "J · Full AURUM-NY PRIME",
)


@dataclass(frozen=True)
class AblationRow:
    name: str
    summary: Summary
    p_pass: float
    prob_expectancy_positive: float

    d_expectancy: float = 0.0
    d_profit_factor: float = 0.0
    d_win_rate: float = 0.0
    d_max_drawdown_r: float = 0.0
    d_pass_probability: float = 0.0
    verdict: str = ""


def _mc_pass_probability(trades: list[Trade], rules: FtmoRules, paths: int, seed: int) -> float:
    days = group_by_day(
        [t.date for t in trades],
        [t.realized_r for t in trades],
        [t.mae_r for t in trades],
    )
    return run_monte_carlo(days, rules, paths=paths, seed=seed).p_pass


def build_table(
    runs: dict[str, list[Trade]],
    baseline: str | None = None,
    rules: FtmoRules | None = None,
    mc_paths: int = 2_000,
    bootstrap_samples: int = 2_000,
    seed: int = 20260825,
) -> list[AblationRow]:
    """Compare ablation runs against a baseline (default: the first in order).

    `mc_paths` and `bootstrap_samples` default lower than the headline numbers
    in S64/S65 because this table runs many configurations. Re-run the winner
    at full resolution before believing it.
    """
    rules = rules or FtmoRules()
    ordered = [name for name in ABLATION_ORDER if name in runs]
    ordered += [name for name in runs if name not in ordered]
    if not ordered:
        return []
    base_name = baseline or ordered[0]

    rows: list[AblationRow] = []
    for name in ordered:
        trades = runs[name]
        r_values = [t.realized_r for t in trades]
        rows.append(
            AblationRow(
                name=name,
                summary=summarize(r_values, [t.mae_r for t in trades], [t.mfe_r for t in trades]),
                p_pass=_mc_pass_probability(trades, rules, mc_paths, seed),
                prob_expectancy_positive=bootstrap_expectancy(
                    r_values, samples=bootstrap_samples, seed=seed
                ).prob_positive,
            )
        )

    base = next(row for row in rows if row.name == base_name)
    out: list[AblationRow] = []
    for row in rows:
        d_exp = row.summary.expectancy_r - base.summary.expectancy_r
        d_pass = row.p_pass - base.p_pass
        d_dd = row.summary.max_drawdown_r - base.summary.max_drawdown_r
        if row.name == base_name:
            verdict = "baseline"
        elif row.summary.n < 30:
            verdict = "INSUFFICIENT SAMPLE"
        elif d_exp > 0.05 and row.prob_expectancy_positive >= 0.90:
            verdict = "keep · improves expectancy"
        elif d_dd < 0 and d_exp > -0.05:
            verdict = "keep · risk-control benefit"
        elif d_exp < -0.05:
            verdict = "DROP · costs expectancy"
        else:
            verdict = "unproven · no measurable value"
        out.append(
            AblationRow(
                name=row.name,
                summary=row.summary,
                p_pass=row.p_pass,
                prob_expectancy_positive=row.prob_expectancy_positive,
                d_expectancy=d_exp,
                d_profit_factor=row.summary.profit_factor - base.summary.profit_factor,
                d_win_rate=row.summary.win_rate - base.summary.win_rate,
                d_max_drawdown_r=d_dd,
                d_pass_probability=d_pass,
                verdict=verdict,
            )
        )
    return out


def format_table(rows: list[AblationRow]) -> str:
    header = (
        f"{'configuration':<26}{'N':>5}{'win%':>7}{'exp R':>8}{'ΔexpR':>8}"
        f"{'PF':>7}{'maxDD R':>9}{'P(pass)':>9}{'ΔP':>8}  verdict"
    )
    lines = [header, "-" * len(header)]
    for row in rows:
        s = row.summary
        lines.append(
            f"{row.name:<26}{s.n:>5}{s.win_rate * 100:>6.1f}%{s.expectancy_r:>8.3f}"
            f"{row.d_expectancy:>+8.3f}{s.profit_factor:>7.2f}{s.max_drawdown_r:>9.2f}"
            f"{row.p_pass * 100:>8.1f}%{row.d_pass_probability * 100:>+7.1f}%  {row.verdict}"
        )
    return "\n".join(lines)


@dataclass(frozen=True)
class StabilityPoint:
    value: float
    summary: Summary


def stability_surface(runs: dict[float, list[Trade]]) -> list[StabilityPoint]:
    """S70. One parameter, several values, expectancy at each.

    Read it for a plateau, not a peak. An isolated maximum surrounded by weak
    neighbours is the signature of a curve fit, and the plateau check below says
    so out loud.
    """
    return [
        StabilityPoint(value=value, summary=summarize([t.realized_r for t in runs[value]]))
        for value in sorted(runs)
    ]


def plateau_verdict(points: list[StabilityPoint], min_neighbours: int = 2) -> str:
    """Is the best parameter value supported by its neighbours?"""
    if len(points) < 3:
        return "INSUFFICIENT POINTS — perturb at least three values (S70)"
    best = max(range(len(points)), key=lambda i: points[i].summary.expectancy_r)
    best_exp = points[best].summary.expectancy_r
    neighbours = [
        points[i].summary.expectancy_r
        for i in (best - 1, best + 1)
        if 0 <= i < len(points)
    ]
    supported = sum(1 for value in neighbours if value > 0 and value >= 0.5 * best_exp)
    if best in (0, len(points) - 1):
        return "EDGE PEAK — the optimum sits at the edge of the tested range; widen it"
    if supported >= min(min_neighbours, len(neighbours)):
        return "PLATEAU — neighbouring values hold up"
    return "ISOLATED PEAK — reject; this is a curve fit (S70)"
