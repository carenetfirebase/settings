"""AURUM-NY PRIME external validation CLI (deliverable J).

Everything the specification asks Pine not to fake:

    python -m validation.aurum_validate report   trades.csv
    python -m validation.aurum_validate montecarlo trades.csv --blocks 3,5,10
    python -m validation.aurum_validate walkforward trades.csv --train 12 --test 3
    python -m validation.aurum_validate ablation  A=a.csv B=b.csv ... J=j.csv
    python -m validation.aurum_validate stability 1.00=a.csv 1.25=b.csv 1.50=c.csv
    python -m validation.aurum_validate lint      ../AURUM_NY_PRIME.pine

`report` is the one to run first. It prints the TARGET block and the VERIFIED
block separately, as S87 requires, and it will tell you when your sample is too
small to support the conclusion you were hoping for.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):  # allow `python aurum_validate.py`
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "validation"

from .ablation import build_table, format_table, plateau_verdict, stability_surface
from .montecarlo import (
    FtmoRules,
    block_bootstrap_expectancy,
    group_by_day,
    run_monte_carlo,
)
from .stats import bootstrap_expectancy, summarize
from .trades import Trade, chronological_split, load, walk_forward_windows

TARGET_BLOCK = """
TARGET (what was asked for — NOT a result)
  win rate                     70%+
  initial reward opportunity   1.5R minimum
  runner potential             3R–7R, occasionally
  FTMO pass probability        high
""".rstrip()


def _summary_block(title: str, trades: list[Trade], bootstrap: int, seed: int) -> str:
    r_values = [t.realized_r for t in trades]
    s = summarize(r_values, [t.mae_r for t in trades], [t.mfe_r for t in trades])
    if s.n == 0:
        return f"\n{title}\n  no trades"
    boot = bootstrap_expectancy(r_values, samples=bootstrap, seed=seed)
    return f"""
{title}
  trades                       {s.n}  ({s.sample_label})
  win rate                     {s.win_rate * 100:.1f}%   95% Wilson CI {s.win_rate_ci.low * 100:.1f}% – {s.win_rate_ci.high * 100:.1f}%
  expectancy                   {s.expectancy_r:+.3f}R
  bootstrap expectancy         mean {boot.mean:+.3f}R   median {boot.median:+.3f}R   [{boot.p5:+.3f}, {boot.p95:+.3f}]
  P(expectancy > 0)            {boot.prob_positive * 100:.1f}%
  profit factor                {s.profit_factor:.2f}
  average win / loss           {s.avg_win_r:.2f}R / {s.avg_loss_r:.2f}R   realised R:R {s.realized_reward_risk:.2f}
  net                          {s.net_r:+.1f}R
  max / average drawdown       {s.max_drawdown_r:.2f}R / {s.avg_drawdown_r:.2f}R   Calmar-like {s.calmar_like:.2f}
  consecutive losses / wins    {s.max_consecutive_losses} / {s.max_consecutive_wins}
  MAE / MFE                    {s.avg_mae_r:.2f}R / {s.avg_mfe_r:.2f}R
  winner MAE / loser MFE       {s.avg_winner_mae_r:.2f}R / {s.avg_loser_mfe_r:.2f}R
  average hold                 {sum(t.hold_bars for t in trades) / s.n:.1f} bars
""".rstrip()


def _verdict(trades: list[Trade], oos: list[Trade], bootstrap: int, seed: int) -> str:
    s = summarize([t.realized_r for t in oos or trades])
    boot = bootstrap_expectancy([t.realized_r for t in oos or trades], samples=bootstrap, seed=seed)
    checks = [
        ("profit factor ≥ 1.5", s.profit_factor >= 1.5),
        ("expectancy ≥ +0.25R", s.expectancy_r >= 0.25),
        ("P(expectancy > 0) ≥ 95%", boot.prob_positive >= 0.95),
        ("out-of-sample N ≥ 100", s.n >= 100),
    ]
    lines = ["\nS86 SUCCESS CRITERIA (measured on untouched out-of-sample)"]
    for label, ok in checks:
        lines.append(f"  [{'x' if ok else ' '}] {label}")
    if all(ok for _, ok in checks):
        lines.append("\n  VERDICT: promising. Proceed to forward testing (S74) — not to live capital.")
    elif s.n < 100:
        lines.append("\n  VERDICT: PRELIMINARY. The sample is too small to conclude anything (S73).")
    else:
        lines.append("\n  VERDICT: not demonstrated. Do not deploy; do not re-optimise on this data (S85).")
    return "\n".join(lines)


def cmd_report(args: argparse.Namespace) -> int:
    trades = load(args.csv)
    split = chronological_split(trades, args.dev, args.val)
    print(TARGET_BLOCK)
    print("\nACTUAL VERIFIED RESULT (whatever the data genuinely produce)")
    print("\nCHRONOLOGICAL SPLIT (S68)")
    for line in split.describe().splitlines():
        print(f"  {line}")
    print(_summary_block("ALL TRADES", trades, args.bootstrap, args.seed))
    print(_summary_block("DEVELOPMENT 60%", split.development, args.bootstrap, args.seed))
    print(_summary_block("VALIDATION 20%", split.validation, args.bootstrap, args.seed))
    print(_summary_block("FINAL UNTOUCHED OUT-OF-SAMPLE 20%", split.out_of_sample, args.bootstrap, args.seed))
    print(_verdict(trades, split.out_of_sample, args.bootstrap, args.seed))
    if args.json:
        payload = {
            "all": summarize([t.realized_r for t in trades]).as_dict(),
            "out_of_sample": summarize([t.realized_r for t in split.out_of_sample]).as_dict(),
        }
        Path(args.json).write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
        print(f"\nwrote {args.json}")
    return 0


def cmd_montecarlo(args: argparse.Namespace) -> int:
    trades = load(args.csv)
    days = group_by_day(
        [t.date for t in trades],
        [t.realized_r for t in trades],
        [t.mae_r for t in trades],
    )
    rules = FtmoRules(
        account=args.account,
        target_pct=args.target,
        daily_loss_pct=args.daily_loss,
        max_loss_pct=args.max_loss,
        min_trading_days=args.min_days,
        max_days=args.horizon,
    )
    print(f"trading days in sample: {len(days)}   trades: {len(trades)}")
    print(f"account {rules.account:,.0f}  target {rules.target_pct}%  "
          f"daily {rules.daily_loss_pct}%  max {rules.max_loss_pct}%  "
          f"min days {rules.min_trading_days}  horizon {rules.max_days}")
    for block in [int(b) for b in args.blocks.split(",")]:
        result = run_monte_carlo(days, rules, paths=args.paths, block=block, seed=args.seed)
        print(
            f"\nblock = {block} trading days   paths = {result.paths}\n"
            f"  P(pass before failure)     {result.p_pass * 100:.2f}%\n"
            f"  P(daily-loss violation)    {result.p_daily_loss * 100:.2f}%\n"
            f"  P(max-loss violation)      {result.p_max_loss * 100:.2f}%\n"
            f"  P(no result in horizon)    {result.p_timeout * 100:.2f}%\n"
            f"  days to pass  median {result.median_days_to_pass:.0f}   95th {result.p95_days_to_pass:.0f}\n"
            f"  max drawdown  median {result.median_max_drawdown:,.0f}   95th {result.p95_max_drawdown:,.0f}\n"
            f"  {result.note}"
        )
        boot = block_bootstrap_expectancy(days, samples=args.paths, block=block, seed=args.seed)
        if boot:
            print(
                f"  block-bootstrap expectancy  mean {boot['mean']:+.3f}R  "
                f"[{boot['p5']:+.3f}, {boot['p95']:+.3f}]  P(>0) {boot['prob_positive'] * 100:.1f}%"
            )
    print("\nSet the Pine drawdown kill switch to the 95th-percentile drawdown above (S76).")
    return 0


def cmd_walkforward(args: argparse.Namespace) -> int:
    trades = load(args.csv)
    windows = walk_forward_windows(trades, args.train, args.test)
    if not windows:
        print("not enough history for a single walk-forward window")
        return 1
    print(f"{'#':>3} {'train':<26}{'test':<26}{'N':>5}{'win%':>7}{'exp R':>8}{'PF':>7}")
    print("-" * 82)
    pooled: list[float] = []
    for window in windows:
        s = summarize([t.realized_r for t in window.test])
        pooled.extend(t.realized_r for t in window.test)
        print(
            f"{window.index:>3} {window.train_start + '→' + window.train_end:<26}"
            f"{window.test_start + '→' + window.test_end:<26}"
            f"{s.n:>5}{s.win_rate * 100:>6.1f}%{s.expectancy_r:>8.3f}{s.profit_factor:>7.2f}"
        )
    aggregate = summarize(pooled)
    print("-" * 82)
    print(
        f"aggregate forward result: N {aggregate.n}  win {aggregate.win_rate * 100:.1f}% "
        f"(CI {aggregate.win_rate_ci.low * 100:.1f}–{aggregate.win_rate_ci.high * 100:.1f}%)  "
        f"expectancy {aggregate.expectancy_r:+.3f}R  PF {aggregate.profit_factor:.2f}"
    )
    positive = sum(1 for w in windows if summarize([t.realized_r for t in w.test]).expectancy_r > 0)
    print(f"windows with positive expectancy: {positive}/{len(windows)}")
    return 0


def _parse_named(pairs: list[str]) -> dict[str, list[Trade]]:
    runs: dict[str, list[Trade]] = {}
    for pair in pairs:
        name, _, path = pair.partition("=")
        if not path:
            raise SystemExit(f"expected NAME=path.csv, got {pair!r}")
        runs[name] = load(path)
    return runs


def cmd_ablation(args: argparse.Namespace) -> int:
    runs = _parse_named(args.runs)
    rows = build_table(runs, baseline=args.baseline, mc_paths=args.paths, seed=args.seed)
    print(format_table(rows))
    print("\nA component stays only if it improves robustness or defends risk (S71, S85).")
    return 0


def cmd_stability(args: argparse.Namespace) -> int:
    runs = {float(name): trades for name, trades in _parse_named(args.runs).items()}
    points = stability_surface(runs)
    print(f"{'value':>10}{'N':>6}{'win%':>8}{'exp R':>9}{'PF':>7}{'maxDD R':>10}")
    print("-" * 50)
    for point in points:
        s = point.summary
        print(
            f"{point.value:>10.3f}{s.n:>6}{s.win_rate * 100:>7.1f}%{s.expectancy_r:>9.3f}"
            f"{s.profit_factor:>7.2f}{s.max_drawdown_r:>10.2f}"
        )
    print(f"\n{plateau_verdict(points)}")
    return 0


def cmd_lint(args: argparse.Namespace) -> int:
    from .pine_lint import lint

    findings = lint(Path(args.pine).read_text(encoding="utf-8"))
    for finding in findings:
        print(finding)
    print(f"\n{len(findings)} finding(s)")
    return 1 if findings else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="aurum_validate", description=__doc__)
    parser.add_argument("--seed", type=int, default=20260825, help="deterministic resampling seed")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("report", help="core statistics, chronological split, verdict")
    p.add_argument("csv")
    p.add_argument("--dev", type=float, default=0.60)
    p.add_argument("--val", type=float, default=0.20)
    p.add_argument("--bootstrap", type=int, default=10_000)
    p.add_argument("--json", default=None, help="also write a JSON summary here")
    p.set_defaults(func=cmd_report)

    p = sub.add_parser("montecarlo", help="block-bootstrap FTMO pass simulation")
    p.add_argument("csv")
    p.add_argument("--paths", type=int, default=10_000)
    p.add_argument("--blocks", default="3,5,10")
    p.add_argument("--account", type=float, default=100_000)
    p.add_argument("--target", type=float, default=10.0)
    p.add_argument("--daily-loss", type=float, default=5.0)
    p.add_argument("--max-loss", type=float, default=10.0)
    p.add_argument("--min-days", type=int, default=4)
    p.add_argument("--horizon", type=int, default=120)
    p.set_defaults(func=cmd_montecarlo)

    p = sub.add_parser("walkforward", help="rolling train/test windows")
    p.add_argument("csv")
    p.add_argument("--train", type=int, default=12, help="training months")
    p.add_argument("--test", type=int, default=3, help="forward months")
    p.set_defaults(func=cmd_walkforward)

    p = sub.add_parser("ablation", help="compare ablation runs (NAME=path.csv ...)")
    p.add_argument("runs", nargs="+")
    p.add_argument("--baseline", default=None)
    p.add_argument("--paths", type=int, default=2_000)
    p.set_defaults(func=cmd_ablation)

    p = sub.add_parser("stability", help="parameter stability surface (VALUE=path.csv ...)")
    p.add_argument("runs", nargs="+")
    p.set_defaults(func=cmd_stability)

    p = sub.add_parser("lint", help="static checks on the Pine source")
    p.add_argument("pine")
    p.set_defaults(func=cmd_lint)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
