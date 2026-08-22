"""``score_company`` — the scoring entry point.

    score_company(cik, as_of, weights, facts) -> ScoreRow

A **pure function**. It takes no session, opens no file, and reads no clock:
the fact set is materialized before it is called, filtered on
``public_available_at <= as_of``. That is what makes Phase 3's two hardest
criteria structural rather than hopeful —

* criterion 1, byte-identical reruns: nothing varies between calls;
* criterion 3, no ``datetime.now`` under ``scoring/``: there is nothing here
  that would want it.

``weights_version`` and ``weights_hash`` are written from the loaded weights
rather than passed by the caller, so a score row cannot be produced without
its provenance or be stamped with a version it was not computed under.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any

from imt.db.enums import ContradictionStatus, NormalizationMethod, SignalCategory
from imt.scoring.categories import SCORE_PRECISION, SubSignal, combine_category
from imt.scoring.composite import compute_composites, compute_data_quality
from imt.scoring.contradiction import ContradictionResult, evaluate
from imt.scoring.convergence import CategoryScore, ConvergenceResult, compute_convergence
from imt.scoring.weights import Weights


@dataclass(frozen=True, slots=True)
class FactSet:
    """Everything known about one company as of one date.

    Assembled by a query filtered on ``public_available_at <= as_of``, so a
    backtest and a live run take the same path and the look-ahead question is
    answered once, at materialization, rather than in every scorer.
    """

    cik: str
    as_of: date
    #: Sub-signals per evidence category, already normalized to 0-100.
    category_signals: dict[SignalCategory, list[SubSignal]] = field(default_factory=dict)
    #: Categories with no ingested data at all. Distinct from a category that
    #: was examined and scored zero.
    unavailable_categories: frozenset[SignalCategory] = frozenset()
    #: Events sharing a real-world occurrence across categories.
    underlying_event_keys: dict[SignalCategory, frozenset[str]] = field(default_factory=dict)
    #: Inputs for the contradiction checks.
    contradiction_facts: dict[str, Any] = field(default_factory=dict)
    #: Datasets actually ingested, gating which checks may run.
    available_data: frozenset[str] = frozenset()
    #: Per-source feed health, 0-100 (SPEC §10).
    feed_health: float = 100.0
    #: Which normalization produced the inputs.
    normalization: NormalizationMethod = NormalizationMethod.FALLBACK_THRESHOLD


@dataclass(frozen=True, slots=True)
class ScoreRow:
    cik: str
    as_of: date
    research_priority: float
    confidence: float
    convergence: float
    contradiction: float
    freshness: float
    data_quality: float
    base: float
    category_scores: dict[str, float]
    categories_cleared: int
    categories_total: int
    weights_version: str
    weights_hash: str
    normalization: NormalizationMethod
    convergence_detail: ConvergenceResult
    contradiction_detail: ContradictionResult

    def to_export_row(self) -> dict[str, Any]:
        """Flat dict for the reproducibility export.

        Keys sorted and floats fixed to a set precision, because Phase 3
        criterion 1 compares exported CSV bytes and an unrounded float would
        make two identical runs differ in the last digit.
        """
        row: dict[str, Any] = {
            "cik": self.cik,
            "as_of": self.as_of.isoformat(),
            "research_priority": f"{self.research_priority:.{SCORE_PRECISION}f}",
            "confidence": f"{self.confidence:.{SCORE_PRECISION}f}",
            "convergence": f"{self.convergence:.{SCORE_PRECISION}f}",
            "contradiction": f"{self.contradiction:.{SCORE_PRECISION}f}",
            "freshness": f"{self.freshness:.{SCORE_PRECISION}f}",
            "data_quality": f"{self.data_quality:.{SCORE_PRECISION}f}",
            "base": f"{self.base:.{SCORE_PRECISION}f}",
            "categories_cleared": self.categories_cleared,
            "categories_total": self.categories_total,
            "weights_version": self.weights_version,
            "weights_hash": self.weights_hash,
            "normalization": self.normalization.value,
        }
        for category in sorted(self.category_scores):
            row[f"cat_{category}"] = f"{self.category_scores[category]:.{SCORE_PRECISION}f}"
        return row


def score_company(
    cik: str,
    as_of: date,
    weights: Weights,
    facts: FactSet,
    *,
    freshness: float = 100.0,
) -> ScoreRow:
    """Score one company as of one date. Deterministic, given the same inputs."""
    category_scores: list[CategoryScore] = []

    # Sorted: the iteration order of a dict keyed by enum members is insertion
    # order, which depends on how the fact set was assembled.
    for category in sorted(SignalCategory, key=lambda c: c.value):
        if category in facts.unavailable_categories:
            category_scores.append(
                CategoryScore(category=category, score=0.0, actor_count=0, available=False)
            )
            continue

        signals = facts.category_signals.get(category, [])
        category_scores.append(
            CategoryScore(
                category=category,
                score=combine_category(signals),
                actor_count=len({s.actor_key for s in signals}),
                underlying_event_keys=facts.underlying_event_keys.get(category, frozenset()),
                available=True,
            )
        )

    convergence = compute_convergence(category_scores, weights)

    contradiction = evaluate(
        facts.contradiction_facts,
        as_of,
        weights,
        available_data=facts.available_data,
    )

    available_categories = sum(1 for c in category_scores if c.available)
    category_coverage = available_categories / len(SignalCategory)

    data_quality = compute_data_quality(
        feed_health=facts.feed_health,
        contradiction_coverage=contradiction.coverage,
        category_coverage=category_coverage,
    )

    composites = compute_composites(
        category_scores,
        convergence=convergence.value,
        contradiction=contradiction.score,
        data_quality=data_quality,
        category_coverage=category_coverage,
        normalization=facts.normalization,
        weights=weights,
    )

    return ScoreRow(
        cik=cik,
        as_of=as_of,
        research_priority=composites.research_priority,
        confidence=composites.confidence,
        convergence=convergence.value,
        contradiction=contradiction.score,
        freshness=round(freshness, SCORE_PRECISION),
        data_quality=data_quality,
        base=composites.base,
        category_scores={
            entry.category.value: entry.score for entry in category_scores if entry.available
        },
        categories_cleared=convergence.categories_cleared,
        categories_total=convergence.categories_total,
        # Written from the loaded weights, never passed in -- a score row
        # cannot be stamped with a version it was not computed under.
        weights_version=weights.version,
        weights_hash=weights.file_hash,
        normalization=facts.normalization,
        convergence_detail=convergence,
        contradiction_detail=contradiction,
    )


def unavailable_check_ids(row: ScoreRow) -> tuple[str, ...]:
    """Checks that could not run. Rendered beside the contradiction score."""
    return tuple(
        outcome.check_id
        for outcome in row.contradiction_detail.outcomes
        if outcome.status is ContradictionStatus.UNAVAILABLE
    )
