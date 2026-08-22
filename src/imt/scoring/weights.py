"""Loading and validating ``config/weights.yaml``.

Everything in that file is a hypothesis (SPEC §6.8), but two of its properties
are not negotiable, and both fail *silently* if violated — the system keeps
producing numbers, they are just wrong. So they are checked at load and the
process refuses to start.

**1. Category weights must not be normalized to sum to 1.**

    Convergence = 100 * (1 - exp(-lambda * sum_i(w_i * C_i/100 * [C_i >= tau])))

With lambda = 0.55, SPEC §6.4's calibration (three strong independent
categories ~= 75, five ~= 92) requires w_i ~= 0.88 each, summing to ~8.8 across
ten categories. Normalized to 1.0 (w = 0.1 each), the same inputs produce
Convergence 15 and 24. Nothing errors; the ranking just stops meaning anything.
Anyone tidying the file toward a conventional weighted average introduces this.

**2. No single category weight may exceed 1.05.**

Phase 3's core correctness test requires five signals from *one* category to
score Convergence < 45 — that is the entire premise of the product. A single
category at full strength produces:

    Convergence = 100 * (1 - exp(-0.55 * w))

which crosses 45 at w = 1.087. Weighting insider activity above the others is
the obvious thing to want, and it is exactly what breaks the test.
"""

from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from imt.core.config import config_dir
from imt.db.enums import SignalCategory

#: Sum of category weights within this distance of 1.0 is treated as the
#: normalization mistake rather than a deliberate choice.
NORMALIZED_SUM_TOLERANCE = 0.15

#: Above this, one category alone clears the Phase 3 convergence bound.
MAX_SINGLE_CATEGORY_WEIGHT = 1.05

#: The bound itself, derived rather than hardcoded, so the reason survives.
_ONE_CATEGORY_CONVERGENCE_CEILING = 45.0


class WeightsValidationError(ValueError):
    """Raised at load. Never caught and defaulted -- a bad weights file stops the run."""


@dataclass(frozen=True, slots=True)
class Weights:
    version: str
    file_hash: str
    tau: float
    lambda_: float
    category_weights: dict[str, float]
    composites: dict[str, dict[str, float]]
    base_weights: dict[str, float]
    convergence_floor: float
    contradiction_penalty: float
    confidence_contradiction_penalty: float
    threshold_normalization_penalty: float
    freshness_half_life_days: dict[str, float]
    min_observations: int
    trailing_months: int
    thresholds: dict[str, list[tuple[float, float]]]
    contradiction_checks: dict[str, dict[str, Any]]

    def weight_for(self, category: SignalCategory) -> float:
        return self.category_weights.get(category.value, 0.0)

    def half_life(self, event_type: str) -> float:
        try:
            return self.freshness_half_life_days[event_type]
        except KeyError as exc:
            # A missing half-life must not default to something plausible --
            # SPEC §6.5 is explicit that decay is per-source, never shared.
            raise KeyError(
                f"No freshness half-life configured for event type {event_type!r}. "
                f"SPEC §6.5 requires a per-event half-life; there is no default."
            ) from exc


def _single_category_convergence(weight: float, lambda_: float) -> float:
    return 100.0 * (1.0 - math.exp(-lambda_ * weight))


def _validate(raw: dict[str, Any], weights: Weights) -> None:
    problems: list[str] = []

    total = sum(weights.category_weights.values())
    if abs(total - 1.0) <= NORMALIZED_SUM_TOLERANCE:
        problems.append(
            f"category_weights sum to {total:.3f}, which looks normalized to 1.0. "
            f"They must NOT be. With lambda={weights.lambda_}, normalized weights make "
            f"three strong categories score ~15 and five score ~24, against the "
            f"SPEC §6.4 calibration of ~75 and ~92. Expected sum is roughly "
            f"{0.88 * len(weights.category_weights):.1f}. See the comment block at the "
            f"top of config/weights.yaml."
        )

    for name, weight in sorted(weights.category_weights.items()):
        if weight > MAX_SINGLE_CATEGORY_WEIGHT:
            reached = _single_category_convergence(weight, weights.lambda_)
            problems.append(
                f"category_weights.{name} = {weight} exceeds the maximum of "
                f"{MAX_SINGLE_CATEGORY_WEIGHT}. One category at full strength would "
                f"reach Convergence {reached:.1f}, above the "
                f"{_ONE_CATEGORY_CONVERGENCE_CEILING:.0f} bound that Phase 3's core "
                f"correctness test enforces. A single loud "
                f"source must never look like convergence."
            )
        if weight < 0:
            problems.append(f"category_weights.{name} is negative")

    known = {c.value for c in SignalCategory}
    unknown = set(weights.category_weights) - known
    if unknown:
        problems.append(f"unknown categories in category_weights: {sorted(unknown)}")
    missing = known - set(weights.category_weights)
    if missing:
        problems.append(f"categories missing from category_weights: {sorted(missing)}")

    if not 0.0 <= weights.tau <= 100.0:
        problems.append(f"convergence.tau must be within [0, 100], got {weights.tau}")
    if weights.lambda_ <= 0:
        problems.append(f"convergence.lambda_ must be positive, got {weights.lambda_}")

    base_total = sum(weights.base_weights.values())
    if abs(base_total - 1.0) > 0.001:
        # base_weights ARE a weighted mean, so here summing to 1 is correct.
        problems.append(f"base_weights must sum to 1.0, got {base_total:.4f}")

    for group, members in weights.composites.items():
        group_total = sum(members.values())
        if abs(group_total - 1.0) > 0.001:
            problems.append(f"composites.{group} must sum to 1.0, got {group_total:.4f}")

    version = raw.get("weights_version")
    if not isinstance(version, str) or version.count(".") != 2:
        problems.append(f"weights_version must be semver, got {version!r}")

    if problems:
        raise WeightsValidationError(
            "config/weights.yaml is invalid:\n  - " + "\n  - ".join(problems)
        )


def _thresholds(raw: dict[str, Any]) -> dict[str, list[tuple[float, float]]]:
    out: dict[str, list[tuple[float, float]]] = {}
    for key, points in (raw.get("thresholds") or {}).items():
        parsed = [(float(x), float(y)) for x, y in points]
        parsed.sort(key=lambda pair: pair[0])
        out[key] = parsed
    return out


def load_weights(path: Path | None = None) -> Weights:
    """Load, validate, and hash. Raises rather than defaulting."""
    target = path or config_dir() / "weights.yaml"
    payload = target.read_bytes()
    raw = yaml.safe_load(payload.decode("utf-8"))
    if not isinstance(raw, dict):
        raise WeightsValidationError(f"{target} must contain a mapping")

    convergence = raw.get("convergence", {})
    rp = raw.get("research_priority", {})
    conf = raw.get("confidence", {})
    norm = raw.get("normalization", {})

    weights = Weights(
        version=str(raw.get("weights_version", "")),
        # Recorded on every score row alongside the version, so a file edited
        # without bumping its version is detectable after the fact.
        file_hash=hashlib.sha256(payload).hexdigest(),
        tau=float(convergence.get("tau", 60.0)),
        lambda_=float(convergence.get("lambda_", 0.55)),
        category_weights={k: float(v) for k, v in (raw.get("category_weights") or {}).items()},
        composites={
            group: {k: float(v) for k, v in members.items()}
            for group, members in (raw.get("composites") or {}).items()
        },
        base_weights={k: float(v) for k, v in (raw.get("base_weights") or {}).items()},
        convergence_floor=float(rp.get("convergence_floor", 0.5)),
        contradiction_penalty=float(rp.get("contradiction_penalty", 0.6)),
        confidence_contradiction_penalty=float(conf.get("contradiction_penalty", 0.5)),
        threshold_normalization_penalty=float(conf.get("threshold_normalization_penalty", 0.7)),
        freshness_half_life_days={
            k: float(v) for k, v in (raw.get("freshness_half_life_days") or {}).items()
        },
        min_observations=int(norm.get("min_observations", 500)),
        trailing_months=int(norm.get("trailing_months", 36)),
        thresholds=_thresholds(raw),
        contradiction_checks=dict(raw.get("contradiction_checks") or {}),
    )
    _validate(raw, weights)
    return weights
