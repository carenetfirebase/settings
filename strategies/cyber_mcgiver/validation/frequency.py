"""Run the v7 reference engine and print the funnel, frequency and analytics.

    python strategies/cyber_mcgiver/validation/frequency.py
    python strategies/cyber_mcgiver/validation/frequency.py --sensitivity

The numbers this prints come from `synthetic` bars, not from OANDA:XAUUSD.
Read the frequency, the funnel and the score distribution; ignore the profit
factor. See docs/03_what_the_synthetic_run_proves.md for exactly which columns
carry information and which do not.
"""

from __future__ import annotations

import argparse
import statistics
import sys
from dataclasses import replace
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import synthetic  # noqa: E402
from reference import (  # noqa: E402
    FAM_NAMES, N_FAM, N_SCORE, SCORE_NAMES, SESS_NAMES, TIER_NAMES,
    Engine, Params, Trade, run, score_bucket,
)

START = date(2016, 8, 26)
END = date(2026, 8, 26)


def _pf(wins: list[float], losses: list[float]) -> str:
    gross_l = -sum(losses)
    if gross_l <= 0.0:
        return "—"
    return f"{sum(wins) / gross_l:.3f}"


def _max_dd_r(trades: list[Trade]) -> float:
    equity = peak = dd = 0.0
    for t in trades:
        equity += t.r_multiple
        peak = max(peak, equity)
        dd = max(dd, peak - equity)
    return dd


def _streaks(trades: list[Trade]) -> tuple[int, int]:
    best = worst = cur_w = cur_l = 0
    for t in trades:
        if t.pnl > 0:
            cur_w, cur_l = cur_w + 1, 0
            best = max(best, cur_w)
        else:
            cur_l, cur_w = cur_l + 1, 0
            worst = max(worst, cur_l)
    return best, worst


def _rule(title: str, width: int = 78) -> str:
    return f"\n{title}\n{'-' * width}"


def report(engine: Engine, params: Params) -> str:
    f, trades = engine.f, engine.trades
    out: list[str] = []
    add = out.append

    add("=" * 78)
    add("CYBER MCGIVER v7 · REFERENCE ENGINE · SYNTHETIC XAUUSD 15m")
    add(f"{START} to {END} · long only · ${params.initial_capital:,.0f}")
    add("=" * 78)
    add("These bars are GENERATED. Frequency, funnel shape and score distribution")
    add("are meaningful. Profit factor and net P&L are not: the generator carries")
    add("no edge, so the exit model is being measured against a random walk.")

    # ---- frequency -----------------------------------------------------------
    days = engine.normal_days
    add(_rule("DAILY FREQUENCY"))
    avg = engine.normal_trades / days if days else 0.0
    cum, median = 0, 0
    for k, n in enumerate(engine.day_hist):
        cum += n
        if cum >= days / 2:
            median = k
            break
    add(f"  total normal trading days          {days:>8}")
    add(f"  short / holiday days excluded      {engine.short_days:>8}")
    add(f"  total trades                       {len(trades):>8}")
    add(f"  average trades / trading day       {avg:>8.3f}   target 1.30 - 1.80")
    add(f"  median trades / trading day        {median:>8}")
    for k in range(4):
        add(f"  days with {k} trade{'s' if k != 1 else ' '}                  {engine.day_hist[k]:>8}   {engine.day_hist[k] / days * 100:>5.1f}%")
    add(f"  days with more than 3              {engine.day_hist[4]:>8}   (hard cap is {params.max_per_day})")
    zero = engine.day_hist[0] / days * 100 if days else 0.0
    add(f"  percentage of days with no trade   {zero:>7.1f}%   guideline 15 - 20%")

    # ---- why the empty days are empty ---------------------------------------
    rows = engine.day_rows
    add(_rule("ZERO-TRADE DAYS · restrictive engine, or no long setup?"))
    add("  A long-only engine cannot trade a day the higher timeframes spend")
    add("  pointing down. Splitting the days by how bullish they were separates")
    add("  'too selective' from 'nothing to buy'.")
    add(f"\n  {'bullish bars on the day':<26}{'days':>7}{'zero-trade':>12}{'trades/day':>12}{'eligible/day':>14}")
    for lo, hi, label in ((0.0, 0.05, "0 - 5%"), (0.05, 0.25, "5 - 25%"), (0.25, 0.50, "25 - 50%"),
                          (0.50, 0.75, "50 - 75%"), (0.75, 1.01, "75 - 100%")):
        sel = [r for r in rows if lo <= r[1] < hi]
        if not sel:
            continue
        z = sum(1 for r in sel if r[0] == 0)
        add(f"  {label:<26}{len(sel):>7}{z / len(sel) * 100:>11.1f}%"
            f"{statistics.mean(r[0] for r in sel):>12.2f}{statistics.mean(r[2] for r in sel):>14.2f}")
    empty = [r for r in rows if r[0] == 0]
    if empty:
        no_cand = sum(1 for r in empty if r[2] == 0)
        add(f"\n  of the {len(empty)} zero-trade days, {no_cand} ({no_cand / len(empty) * 100:.0f}%) produced no eligible")
        add("  candidate at all — the engine was not offered a trade and refused it.")

    # ---- funnel ---------------------------------------------------------------
    add(_rule("DECISION FUNNEL"))
    raw, cand = sum(f.raw), sum(f.candidates)
    passed, taken = sum(f.passed), sum(f.taken)

    def line(label: str, value: int, base: int | None = None) -> None:
        pct = f"{value / base * 100:>7.1f}%" if base else " " * 8
        add(f"  {label:<44}{value:>9}{pct}")

    line("bars processed", f.bars)
    add("  -- stage 1 · raw opportunities")
    line("raw structural events", raw)
    add("  -- stage 2 · candidates")
    line("trigger fired (candidates)", cand, raw)
    line("bars offering more than one candidate", f.multi_bar)
    add("  -- stage 3 · score")
    line("cleared the score floor", passed, cand)
    line("rejected below the score floor", f.score_fail, cand)
    add("  -- stage 4 · mandatory risk gates")
    line("blocked · regime floor", f.block_regime, passed)
    line("blocked · trigger closed too weak", f.block_mom, passed)
    line("blocked · volatility shock", f.block_shock, passed)
    line("rejected · stop wider than max ATR", f.stop_wide, passed)
    line("rejected · stop tighter than min ATR", f.stop_tight, passed)
    line("rejected · not enough reward room", f.room_short, passed)
    line("rejected · anchor already traded", f.block_anchor, passed)
    add("  -- stage 5 · availability (counted per bar)")
    line("blocked · position or order already live", f.block_open)
    line("blocked · daily trade cap", f.block_cap)
    line("blocked · daily loss cutoff", f.block_loss)
    line("blocked · independence cooldown", f.block_cool)
    line("rejected · size below minimum lot", f.size_small)
    line("rejected · daily risk budget exhausted", f.budget_out)
    add("  -- stage 6 · execution")
    line("orders armed", f.armed)
    line("orders filled", f.filled, f.armed)
    line("· of those, filled and exited in one bar", f.same_bar, max(f.filled, 1))
    line("orders expired unfilled", f.arm_expired, f.armed)
    line("orders invalidated before filling", f.arm_voided, f.armed)
    line("trades completed", f.trades)

    # ---- score calibration ----------------------------------------------------
    add(_rule("SCORE CALIBRATION · every candidate, taken or not"))
    add("  'cand/day at or above' is the frequency the engine would offer if the")
    add("  score floor were moved to the bottom of that bucket. Compare it with")
    add("  the 1.30 - 1.80 target before changing anything else.")
    add(f"\n  {'bucket':<12}{'candidates':>12}{'cand/day >=':>13}{'trades':>9}{'win %':>9}{'exp R':>9}{'PF':>9}")
    cum_above = 0
    for b in range(N_SCORE - 1, -1, -1):
        cum_above += f.cand_by_score[b]
        sel = [t for t in trades if score_bucket(t.score) == b]
        wins = [t.r_multiple for t in sel if t.pnl > 0]
        losses = [t.r_multiple for t in sel if t.pnl <= 0]
        win_pct = f"{len(wins) / len(sel) * 100:.1f}%" if sel else "—"
        exp = f"{statistics.mean(t.r_multiple for t in sel):+.3f}" if sel else "—"
        add(f"  {SCORE_NAMES[b]:<12}{f.cand_by_score[b]:>12}{cum_above / days:>13.2f}"
            f"{len(sel):>9}{win_pct:>9}{exp:>9}{_pf(wins, losses):>9}")

    # ---- families -------------------------------------------------------------
    add(_rule("SETUP FAMILY ANALYTICS"))
    add(f"  {'family':<14}{'raw':>8}{'cand':>8}{'>=floor':>9}{'trades':>8}{'win %':>8}{'PF':>8}{'exp R':>9}{'maxDD R':>9}{'scoreW':>8}{'scoreL':>8}")
    for fam in range(N_FAM):
        sel = [t for t in trades if t.family == fam]
        wins = [t for t in sel if t.pnl > 0]
        losses = [t for t in sel if t.pnl <= 0]
        win_pct = f"{len(wins) / len(sel) * 100:.1f}%" if sel else "—"
        exp = f"{statistics.mean(t.r_multiple for t in sel):+.3f}" if sel else "—"
        sw = f"{statistics.mean(t.score for t in wins):.1f}" if wins else "—"
        sl = f"{statistics.mean(t.score for t in losses):.1f}" if losses else "—"
        add(f"  {FAM_NAMES[fam]:<14}{f.raw[fam]:>8}{f.candidates[fam]:>8}{f.passed[fam]:>9}"
            f"{len(sel):>8}{win_pct:>8}{_pf([t.r_multiple for t in wins], [t.r_multiple for t in losses]):>8}"
            f"{exp:>9}{_max_dd_r(sel):>9.2f}{sw:>8}{sl:>8}")

    # ---- tiers and sessions ----------------------------------------------------
    add(_rule("QUALITY TIER"))
    add(f"  {'tier':<8}{'trades':>9}{'share':>9}{'win %':>9}{'exp R':>9}{'risk %':>9}")
    for tier in (3, 2, 1):
        sel = [t for t in trades if t.tier == tier]
        if not trades:
            break
        win_pct = f"{sum(1 for t in sel if t.pnl > 0) / len(sel) * 100:.1f}%" if sel else "—"
        exp = f"{statistics.mean(t.r_multiple for t in sel):+.3f}" if sel else "—"
        risk = {3: params.risk_ap, 2: params.risk_a, 1: params.risk_bp}[tier]
        add(f"  {TIER_NAMES[tier]:<8}{len(sel):>9}{len(sel) / len(trades) * 100:>8.1f}%{win_pct:>9}{exp:>9}{risk:>9.2f}")

    add(_rule("SESSION"))
    add(f"  {'session':<12}{'trades':>9}{'share':>9}{'win %':>9}{'exp R':>9}")
    for sess, name in enumerate(SESS_NAMES):
        sel = [t for t in trades if t.session == sess]
        if not trades:
            break
        win_pct = f"{sum(1 for t in sel if t.pnl > 0) / len(sel) * 100:.1f}%" if sel else "—"
        exp = f"{statistics.mean(t.r_multiple for t in sel):+.3f}" if sel else "—"
        add(f"  {name:<12}{len(sel):>9}{len(sel) / len(trades) * 100:>8.1f}%{win_pct:>9}{exp:>9}")

    # ---- performance -----------------------------------------------------------
    add(_rule("PERFORMANCE  (synthetic bars: shape only, never quote these)"))
    if trades:
        wins = [t for t in trades if t.pnl > 0]
        losses = [t for t in trades if t.pnl <= 0]
        rs = [t.r_multiple for t in trades]
        holds = [t.bars_held for t in trades]
        best, worst = _streaks(trades)
        add(f"  trades {len(trades):>6}   wins {len(wins):>6}   losses {len(losses):>6}"
            f"   win rate {len(wins) / len(trades) * 100:>5.1f}%")
        add(f"  profit factor {_pf([t.r_multiple for t in wins], [t.r_multiple for t in losses]):>8}"
            f"   net P&L ${engine.equity - params.initial_capital:>12,.0f}"
            f"   ({(engine.equity / params.initial_capital - 1) * 100:+.1f}%)")
        add(f"  average R {statistics.mean(rs):>+8.3f}   median R {statistics.median(rs):>+8.3f}"
            f"   max drawdown {_max_dd_r(trades):>7.2f} R")
        add(f"  avg winner {statistics.mean(t.r_multiple for t in wins) if wins else 0:>+7.3f} R"
            f"   avg loser {statistics.mean(t.r_multiple for t in losses) if losses else 0:>+7.3f} R")
        add(f"  largest winner {max(rs):>+7.2f} R   largest loser {min(rs):>+7.2f} R")
        add(f"  avg bars held {statistics.mean(holds):>6.1f}   median bars held {statistics.median(holds):>6.0f}")
        add(f"  max consecutive wins {best:>4}   max consecutive losses {worst:>4}")
        add(f"  median MFE {statistics.median(t.mfe_r for t in trades):>6.2f} R"
            f"   median MAE {statistics.median(t.mae_r for t in trades):>6.2f} R")
        for thr in (0.25, 0.50, 1.00, 1.20, 2.00):
            share = sum(1 for t in trades if t.mfe_r >= thr) / len(trades) * 100
            add(f"    share of trades reaching {thr:.2f} R of MFE   {share:>5.1f}%")
    return "\n".join(out)


def sensitivity(bars) -> str:
    """What each throttle is actually worth, one change at a time."""
    base = Params()
    cases = [
        ("baseline", base),
        ("score floor 70", replace(base, thr_bp=70.0)),
        ("score floor 75", replace(base, thr_bp=75.0)),
        ("score floor 80", replace(base, thr_bp=80.0)),
        ("min reward room 1.2R", replace(base, min_room_r=1.2)),
        ("min reward room 2.0R", replace(base, min_room_r=2.0)),
        ("cooldown 0 bars", replace(base, cooldown=0)),
        ("no anchor rule", replace(base, anchor_rule=False)),
        ("regime floor 0.15", replace(base, reg_floor=0.15)),
        ("regime floor 0.45", replace(base, reg_floor=0.45)),
        ("daily cap 2", replace(base, max_per_day=2)),
    ]
    lines = [_rule("SENSITIVITY · one change at a time, everything else at default")]
    lines.append(f"  {'variant':<24}{'trades':>9}{'trades/day':>12}{'zero-day %':>12}{'cand/day':>10}")
    for label, params in cases:
        e = run(bars, params)
        d = max(e.normal_days, 1)
        lines.append(f"  {label:<24}{len(e.trades):>9}{e.normal_trades / d:>12.3f}"
                     f"{e.day_hist[0] / d * 100:>11.1f}%{sum(e.f.passed) / d:>10.2f}")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sensitivity", action="store_true", help="also sweep the throttles")
    ap.add_argument("--seed", type=int, default=20260826)
    ap.add_argument("--out", type=Path, default=None, help="write the report to a file as well")
    args = ap.parse_args(argv[1:])

    bars = synthetic.generate(START, END, seed=args.seed)
    engine = run(bars)
    text = report(engine, Params())
    if args.sensitivity:
        text += "\n" + sensitivity(bars)
    print(text)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
