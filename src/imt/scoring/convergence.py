"""Cross-category convergence. SPEC §6.4.

    raw         = Σ_i w_i * (C_i/100) * 1[C_i ≥ τ]
    Convergence = 100 * (1 - exp(-λ * raw))

The saturating form is the whole point: it makes the fifth agreeing category
worth less than the second, and it makes **one loud category incapable of
producing a high score**. With the shipped weights, one category at full
strength reaches 38, three reach 76, five reach 91.

Two things this module does that the spec does not describe, both found in
Phase 0 (docs/ARCHITECTURE.md §I):

**Cross-category de-duplication.** An 8-K announcing a contract award and the
USAspending record of the same award are two categories by SPEC §6.3's
definition, but one event. Left alone they co-fire and inflate convergence
exactly where the system should be most careful — a company with one piece of
news would look like a company with two independent confirmations. Events
sharing an ``underlying_event_key`` are collapsed to their strongest category
before the sum.

**The τ gate is a cliff, and that is deliberate.** A category at 59.9
contributes nothing and at 60.0 contributes fully. That is what "independent
categories agreeing" means — weak agreement is not agreement — but it makes
the score discontinuous, so the API returns ``convergence_tau`` and the UI
shows which categories cleared.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from imt.db.enums import SignalCategory
from imt.scoring.categories import SCORE_PRECISION
from imt.scoring.weights import Weights


@dataclass(frozen=True, slots=True)
class CategoryScore:
    """One evidence category's combined score, with its provenance."""

    category: SignalCategory
    score: float
    #: Distinct actors behind it. A 90 from five insiders is not a 90 from one.
    actor_count: int
    #: Groups events describing the same underlying occurrence across
    #: categories. None means this category's evidence stands alone.
    underlying_event_keys: frozenset[str] = frozenset()
    available: bool = True

    def clears(self, tau: float) -> bool:
        return self.available and self.score >= tau


@dataclass(frozen=True, slots=True)
class ConvergenceResult:
    value: float
    raw: float
    tau: float
    categories_cleared: int
    categories_total: int
    cleared: tuple[SignalCategory, ...]
    #: Categories dropped because another category already counted the same
    #: underlying event. Surfaced so the number is explainable.
    suppressed_as_duplicate: tuple[SignalCategory, ...] = ()


def deduplicate_across_categories(
    scores: list[CategoryScore],
) -> tuple[list[CategoryScore], list[SignalCategory]]:
    """Collapse categories whose evidence describes the same real-world event.

    When two categories share an ``underlying_event_key``, only the
    strongest-scoring one contributes. The other is reported as suppressed
    rather than silently dropped, because "we saw two things" and "we saw one
    thing twice" is precisely the distinction convergence is supposed to make.
    """
    # Sorted for determinism: which category wins a tie must not depend on
    # input order.
    ordered = sorted(scores, key=lambda c: (-c.score, c.category.value))
    claimed: dict[str, SignalCategory] = {}
    kept: list[CategoryScore] = []
    suppressed: list[SignalCategory] = []

    for entry in ordered:
        collision = next(
            (key for key in sorted(entry.underlying_event_keys) if key in claimed), None
        )
        if collision is not None:
            suppressed.append(entry.category)
            continue
        for key in entry.underlying_event_keys:
            claimed[key] = entry.category
        kept.append(entry)

    return (
        sorted(kept, key=lambda c: c.category.value),
        sorted(suppressed, key=lambda c: c.value),
    )


def compute_convergence(scores: list[CategoryScore], weights: Weights) -> ConvergenceResult:
    """SPEC §6.4, with cross-category de-duplication applied first."""
    kept, suppressed = deduplicate_across_categories(scores)

    raw = 0.0
    cleared: list[SignalCategory] = []
    # Sorted: floating-point addition is not associative either.
    for entry in sorted(kept, key=lambda c: c.category.value):
        if not entry.clears(weights.tau):
            continue
        raw += weights.weight_for(entry.category) * (entry.score / 100.0)
        cleared.append(entry.category)

    value = 100.0 * (1.0 - math.exp(-weights.lambda_ * raw))

    return ConvergenceResult(
        value=round(value, SCORE_PRECISION),
        raw=round(raw, SCORE_PRECISION),
        tau=weights.tau,
        categories_cleared=len(cleared),
        categories_total=len(SignalCategory),
        cleared=tuple(cleared),
        suppressed_as_duplicate=tuple(suppressed),
    )
