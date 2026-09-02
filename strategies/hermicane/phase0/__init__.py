"""HERMICANE v2 — Phase 0 research harness.

Phase 0 exists to answer one question about HERMICANE v1: **which of its
twenty-five constants were measured, and which were guessed?** The answer, as
of v1, is none and all. This package replaces guessing with measurement, or —
where the data cannot be obtained — says so loudly instead of substituting a
plausible number.

The package is deliberately in two halves:

* A **data layer** (`sources`, `loaders`) that knows what every required series
  is, where it comes from, and what to do when it cannot be reached. It never
  silently proxies one series for another, and it never returns revised macro
  data where a first print was asked for.
* A **computation core** (`stats`, `beta`, `panel`, `control`, `filters`,
  `ablation`, `report`) that is pure arithmetic over whatever the data layer
  produced. This half is fully exercised by the test suite and does not care
  where its inputs came from — which is the point, because the constraint today
  is data, not method.

Standard library only, matching the convention set by the AURUM-NY PRIME
validation stack next door: a research tool that cannot be run because a
dependency moved is not a research tool.

Run ``python -m phase0.cli --help`` from ``strategies/hermicane``.
"""

from __future__ import annotations

__all__ = [
    "ablation",
    "beta",
    "control",
    "filters",
    "loaders",
    "panel",
    "pine_lint",
    "report",
    "sources",
    "stats",
    "synthetic",
]
