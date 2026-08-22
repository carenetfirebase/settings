"""Research Priority and Confidence. SPEC §6.7.

    base = w_im*InformedMoney + w_cat*Catalyst + w_fun*Fundamental + w_ctx*Context

    ResearchPriority = base
                     * (0.5 + 0.5 * Convergence/100)
                     * (1 - 0.6 * Contradiction/100)
                     * DataQuality/100

Three multipliers, each doing something a subtraction could not:

* **Convergence** floors at 0.5, so a company with strong evidence in one
  category keeps half its base rather than collapsing. Convergence modulates
  the ranking; it does not replace it.
* **Contradiction** is multiplicative and never netted. Subtracting it would
  let a strong enough bull case cancel out a CFO selling, and the two facts
  would disappear into a single number that shows neither.
* **DataQuality** multiplies directly, so a company whose feeds are stale or
  whose contradiction checks could not run cannot rank highly by construction
  (SPEC §10). This is what stops the least-examined companies floating to the
  top.

Confidence is capped at 70 for the whole of V1, because the ×0.7
threshold-normalization penalty applies to every score until Phase 8 supplies
enough observations for percentile normalization. Any example payload showing
V1 confidence above 70 is arithmetically impossible.
"""

from __future__ import annotations

from dataclasses import dataclass

from imt.db.enums import NormalizationMethod, SignalCategory
from imt.scoring.categories import SCORE_PRECISION
from imt.scoring.convergence import CategoryScore
from imt.scoring.weights import Weights

#: SPEC §6.7. Confidence cannot exceed this while normalization is
#: threshold-based, which is all of V1. A test asserts it.
V1_CONFIDENCE_CAP = 70.0


@dataclass(frozen=True, slots=True)
class CompositeResult:
    base: float
    research_priority: float
    confidence: float
    informed_money: float
    catalyst: float
    fundamental: float
    context: float


def _group_score(members: dict[str, float], scores: dict[SignalCategory, float]) -> float:
    """Weighted mean over a composite group.

    Unlike the convergence weights, these ARE normalized to sum to 1 — this is
    an average, not a saturating sum. Categories with no evidence contribute
    zero rather than being dropped, so a company strong in insider activity
    but silent politically does not get the political weight redistributed to
    make it look better than it is.
    """
    total = 0.0
    for category_name in sorted(members):
        weight = members[category_name]
        total += weight * scores.get(SignalCategory(category_name), 0.0)
    return round(total, SCORE_PRECISION)


def compute_composites(
    category_scores: list[CategoryScore],
    *,
    convergence: float,
    contradiction: float,
    data_quality: float,
    category_coverage: float,
    normalization: NormalizationMethod,
    weights: Weights,
) -> CompositeResult:
    """SPEC §6.7. Pure arithmetic over already-computed inputs."""
    scores = {entry.category: entry.score for entry in category_scores if entry.available}

    informed_money = _group_score(weights.composites["informed_money"], scores)
    catalyst = _group_score(weights.composites["catalyst"], scores)
    fundamental = _group_score(weights.composites["fundamental"], scores)
    context = _group_score(weights.composites["context"], scores)

    base = round(
        weights.base_weights["informed_money"] * informed_money
        + weights.base_weights["catalyst"] * catalyst
        + weights.base_weights["fundamental"] * fundamental
        + weights.base_weights["context"] * context,
        SCORE_PRECISION,
    )

    floor = weights.convergence_floor
    convergence_multiplier = floor + (1.0 - floor) * (convergence / 100.0)
    contradiction_multiplier = 1.0 - weights.contradiction_penalty * (contradiction / 100.0)
    quality_multiplier = data_quality / 100.0

    research_priority = round(
        base * convergence_multiplier * contradiction_multiplier * quality_multiplier,
        SCORE_PRECISION,
    )

    validated = (
        1.0
        if normalization is NormalizationMethod.PERCENTILE
        else weights.threshold_normalization_penalty
    )
    # SPEC §6.7 writes Confidence as
    #     100 * (DataQuality/100) * CategoryCoverage * (1-0.5*Contra/100) * validated
    # but DataQuality (SPEC §10) already contains CategoryCoverage, so the term
    # appears twice and the coverage penalty is squared: at 1 category of 10
    # that is 0.01 rather than 0.10, and Confidence collapses to a rounding
    # error regardless of the evidence. The duplicate is dropped here.
    # `category_coverage` stays in the signature because it is still the right
    # input for the caller to pass -- it reaches Confidence through
    # DataQuality.
    confidence = round(
        100.0
        * (data_quality / 100.0)
        * (1.0 - weights.confidence_contradiction_penalty * (contradiction / 100.0))
        * validated,
        SCORE_PRECISION,
    )

    return CompositeResult(
        base=base,
        research_priority=research_priority,
        confidence=confidence,
        informed_money=informed_money,
        catalyst=catalyst,
        fundamental=fundamental,
        context=context,
    )


def compute_data_quality(
    *,
    feed_health: float,
    contradiction_coverage: float,
    category_coverage: float,
) -> float:
    """SPEC §10, extended with contradiction coverage (ARCHITECTURE §E).

    Coverage-weighted feed health. Contradiction coverage is folded in because
    a company whose disconfirming checks could not run has not really been
    examined, and DataQuality is the multiplier that keeps it out of the top
    of the ranking.
    """
    return round(
        100.0 * (feed_health / 100.0) * contradiction_coverage * category_coverage,
        SCORE_PRECISION,
    )
