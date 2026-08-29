"""Command line for the Phase 0 harness.

Three commands, matching the three things an operator actually needs to do:

* ``check``  — probe every required host and report what this environment can
  reach. Run it first; if the answer is "nothing", the rest of Phase 0 cannot
  produce constants and the report will say so on its first screen.
* ``run``    — build the panel and write the §3.6 deliverables, either from
  local exports or from the synthetic world.
* ``verify`` — load a constants file and refuse it if it is not calibrated.
  This is the gate Phase 1 should call before generating any Pine.

Run from ``strategies/hermicane``::

    python -m phase0.cli check
    python -m phase0.cli run --synthetic --out out/synthetic
    python -m phase0.cli run --bars xau.csv --yields us2y.csv \\
        --calendar events.csv --daily-gold gold.csv --daily-2y dgs2.csv \\
        --out out/real
    python -m phase0.cli verify out/real/calibrated_constants.json
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .ablation import (
    atr_basis_sensitivity,
    beta_regime_table,
    control_baseline,
    cost_curve,
    run_all_ablations,
    walk_forward,
)
from .control import ControlSpec
from .loaders import load_bars, load_calendar, load_daily, pair_daily
from .panel import PanelInputs, build_panel
from .report import (
    NotCalibrated,
    Phase0Results,
    verify_constants,
    write_outputs,
    write_panel_csv,
    write_panel_parquet,
)
from .sources import BLOCKED_BY_POLICY, REQUIRED_SOURCES, Provenance, probe_all


def cmd_check(args: argparse.Namespace) -> int:
    print("Probing the hosts Phase 0 needs. This makes real requests.\n")
    results = probe_all(timeout=args.timeout)
    width = max(len(r.key) for r in results)
    blocked = 0
    for result in results:
        mark = "ok " if result.reachable else "XX "
        if result.status == BLOCKED_BY_POLICY:
            blocked += 1
        print(f"  {mark} {result.key:<{width}}  {result.host:<28} {result.status:<18} {result.detail}")
    print()
    if blocked:
        print(
            f"{blocked} of {len(results)} hosts were refused by this environment's egress\n"
            "policy. That is a property of where the harness is running, not of the URLs.\n"
            "Obtain the exports elsewhere and feed them to `run` with the file arguments;\n"
            "everything downstream of ingest is offline arithmetic.\n"
        )
        print("What each blocked series costs, and the documented degradation:\n")
        blocked_keys = {r.key for r in results if not r.reachable}
        for source in REQUIRED_SOURCES:
            if source.key not in blocked_keys:
                continue
            print(f"  {source.key} — {source.series}")
            print(f"     needed for : {source.needed_for}")
            print(f"     degradation: {source.degradation}\n")
    return 0


def _load_real(args: argparse.Namespace) -> tuple[PanelInputs, Provenance]:
    missing = [
        name
        for name, value in (
            ("--bars", args.bars),
            ("--yields", args.yields),
            ("--calendar", args.calendar),
            ("--daily-gold", args.daily_gold),
            ("--daily-2y", args.daily_2y),
        )
        if not value
    ]
    if missing:
        raise SystemExit(
            "A real run needs every core series. Missing: "
            + ", ".join(missing)
            + "\nRun `check` to see where each one comes from, or use --synthetic to\n"
            "exercise the harness without claiming a measurement."
        )

    provenance = Provenance(quality="real")
    prices = load_bars(args.bars, "XAUUSD")
    provenance.record("xau_1m", "real", str(args.bars))
    yields = load_bars(args.yields, "US2Y")
    provenance.record("us2y_intraday", "real", str(args.yields))
    events = load_calendar(args.calendar)
    provenance.record("actuals_first_print", "real", str(args.calendar))
    provenance.record("consensus", "real", str(args.calendar))

    gold_daily = load_daily(args.daily_gold)
    provenance.record("gold_daily", "real", str(args.daily_gold))
    dgs2 = load_daily(args.daily_2y)
    provenance.record("dgs2_daily", "real", str(args.daily_2y))
    daily = pair_daily(gold_daily, dgs2)

    dxy = None
    if args.dxy:
        dxy = load_bars(args.dxy, "DXY")
        provenance.record("dxy_1m", "real", str(args.dxy))
    else:
        provenance.record("dxy_1m", "absent", "no --dxy supplied")
        provenance.note(
            "No DXY series was supplied, so the macro-alignment filter is untested "
            "rather than failed. Its ablation row will show no surviving sample."
        )

    if not events:
        raise SystemExit("The calendar contained no events.")
    without_consensus = sum(1 for e in events if not e.has_consensus)
    if without_consensus:
        provenance.note(
            f"{without_consensus} of {len(events)} events carry no consensus. Their "
            "surprise columns are NaN and every surprise-conditioned filter will "
            "reject them; they still count in the control."
        )

    spec = ControlSpec(
        atr_timeframe_minutes=args.atr_timeframe,
        atr_periods=args.atr_periods,
    )
    return PanelInputs(events, prices, yields, daily, dxy, spec), provenance


def _load_synthetic(args: argparse.Namespace) -> tuple[PanelInputs, Provenance]:
    from .synthetic import generate

    world = generate(years=args.years, seed=args.seed)
    spec = ControlSpec(
        atr_timeframe_minutes=args.atr_timeframe,
        atr_periods=args.atr_periods,
    )
    return (
        PanelInputs(world.events, world.prices, world.yields, world.daily, world.dxy, spec),
        world.provenance,
    )


def cmd_run(args: argparse.Namespace) -> int:
    inputs, provenance = (_load_synthetic if args.synthetic else _load_real)(args)

    print(f"Building panel over {len(inputs.events)} events…")
    rows = build_panel(inputs)

    print("Running the control…")
    baseline = control_baseline(rows, resamples=args.resamples)
    print(
        f"  control: n={baseline.estimate.n} mean R {baseline.estimate.mean:+.3f} "
        f"CI {baseline.estimate.ci} ({baseline.health})"
    )

    print("Ablating filters and sweeping thresholds…")
    ablations, sweeps = run_all_ablations(rows, baseline, resamples=args.resamples)

    print("Testing the beta regime thesis…")
    regime = beta_regime_table(rows, window=args.beta_window, resamples=args.resamples)
    print(f"  beta regime: {regime.verdict}")

    print("Costing, splitting, and checking the ATR basis…")
    results = Phase0Results(
        provenance=provenance,
        spec=inputs.spec,
        rows=rows,
        baseline=baseline,
        ablations=ablations,
        sweeps=sweeps,
        regime=regime,
        costs=cost_curve(rows, resamples=args.resamples),
        walk=walk_forward(rows, resamples=args.resamples),
        atr_bases=atr_basis_sensitivity(rows, inputs.prices, spec=inputs.spec, resamples=args.resamples),
    )

    out_dir = Path(args.out)
    written = write_outputs(results, out_dir)
    csv_path = write_panel_csv(rows, out_dir / "panel.csv")
    parquet_path = write_panel_parquet(rows, out_dir / "panel.parquet")

    print("\nWritten:")
    print(f"  {written['report']}")
    print(f"  {written['provenance']}")
    print(f"  {csv_path}")
    if parquet_path:
        print(f"  {parquet_path}")
    else:
        print("  (panel.parquet skipped — pyarrow is not installed; panel.csv holds the same data)")

    if provenance.is_real:
        print(f"  {written['constants']}")
    else:
        print(f"  {written['constants']}")
        print(
            "\nNo calibrated_constants.json was written. This run was not built entirely\n"
            "from real feeds, so nothing in it may be ported to Pine. Phase 1 stays shut."
        )
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    try:
        payload = verify_constants(Path(args.path))
    except NotCalibrated as error:
        print(f"REFUSED: {error}")
        return 1
    panel = payload.get("panel", {})
    print(f"OK: calibrated constants from {payload.get('generated_utc')}")
    print(f"  events traded : {panel.get('events_traded')} of {panel.get('events_total')}")
    print(f"  sample health : {panel.get('sample_health')}")
    print(f"  beta regime   : {payload.get('beta_regime', {}).get('verdict')}")
    print(f"  filters kept  : {len(payload.get('surviving_filters', []))}")
    print(f"  filters cut   : {len(payload.get('deleted_filters', []))}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="phase0", description=__doc__.split("\n")[0])
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="probe the data hosts this environment can reach")
    check.add_argument("--timeout", type=int, default=12)
    check.set_defaults(func=cmd_check)

    run = subparsers.add_parser("run", help="build the panel and write the Phase 0 deliverables")
    run.add_argument("--synthetic", action="store_true", help="use the synthetic world; cannot produce constants")
    run.add_argument("--years", type=int, default=5, help="synthetic only")
    run.add_argument("--seed", type=int, default=20260829, help="synthetic only")
    run.add_argument("--bars", help="1-minute XAUUSD CSV")
    run.add_argument("--yields", help="1-minute US 2Y (or ZT/ZF proxy) CSV")
    run.add_argument("--dxy", help="1-minute DXY CSV (optional)")
    run.add_argument("--calendar", help="event calendar CSV with first-print actuals and consensus")
    run.add_argument("--daily-gold", help="daily gold close CSV")
    run.add_argument("--daily-2y", help="daily DGS2 CSV")
    run.add_argument("--atr-timeframe", type=int, default=ControlSpec().atr_timeframe_minutes)
    run.add_argument("--atr-periods", type=int, default=ControlSpec().atr_periods)
    run.add_argument("--beta-window", type=int, default=90, choices=(60, 90, 120))
    run.add_argument("--resamples", type=int, default=5000)
    run.add_argument("--out", default="out", help="directory for the deliverables")
    run.set_defaults(func=cmd_run)

    verify = subparsers.add_parser("verify", help="refuse a constants file that is not calibrated")
    verify.add_argument("path")
    verify.set_defaults(func=cmd_verify)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
