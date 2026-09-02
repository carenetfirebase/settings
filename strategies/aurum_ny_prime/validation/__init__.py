"""External validation framework for AURUM-NY PRIME v2.0 (S80, deliverable J).

Pine Script does the strategy: signals, sizing, orders, dashboard, and the basic
statistics that have a closed form. Everything whose implementation quality in
Pine would be materially inferior lives here instead — bootstrapped expectancy,
block-bootstrap Monte Carlo, FTMO pass paths, ablation tables, parameter
stability, walk-forward aggregation.

Standard library only. A validation tool that cannot be run because a dependency
moved is not a validation tool.
"""

from __future__ import annotations

__all__ = [
    "ablation",
    "montecarlo",
    "pine_lint",
    "reference",
    "stats",
    "trades",
]
