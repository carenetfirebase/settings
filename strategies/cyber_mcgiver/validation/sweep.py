"""Measure which gate the funnel actually dies at, and what each change buys.

Run after any change to the state machine, before touching TradingView:

    python -m validation.sweep

Fills are on 40,000 simulated 15m bars (~1.5 years of 24h trading) against a
drifting random walk with the real unanimous 1D/4H/1H gate applied. The
absolute numbers are not forecasts of gold — the ratios between rows are the
point.
"""

from __future__ import annotations

from validation.simulate import random_series, run, unanimous

VARIANTS: list[tuple[str, dict]] = [
    ("v2 baseline · P3 = pivot, tol 0.12", {"p3_pivot_only": True}),
    ("v3 default · P3 = any-bar touch, tol 0.12", {}),
    ("P3 = pivot, tol 0.25", {"p3_pivot_only": True, "tol": 0.25}),
    ("P3 = any-bar touch, tol 0.25", {"tol": 0.25}),
    ("… plus body 0.25 / close-loc 0.55", {"tol": 0.25, "body_min": 0.25, "clv_min": 0.55}),
    ("… plus line expiry 40 bars", {"tol": 0.25, "tl_expiry": 40}),
    ("… plus slope ceiling 0.40", {"tol": 0.25, "slope_max": 0.40}),
]


def main() -> None:
    bars = random_series(40_000, seed=7)
    regime = unanimous(bars)
    head = f"{'variant':<44}{'cand':>6}{'P3':>6}{'T4':>6}{'rej':>6}{'fill':>6}"
    print(head)
    print("-" * len(head))
    for label, kwargs in VARIANTS:
        f = run(bars, regime, **kwargs)
        print(f"{label:<44}{f.candidates:>6}{f.p3:>6}{f.t4:>6}{f.rejections:>6}{f.filled:>6}")


if __name__ == "__main__":
    main()
