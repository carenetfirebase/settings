"""Within-category combination. SPEC §6.3.

Sub-signals inside one category combine with diminishing returns:

    C_i = 100 * (1 - Π_j (1 - s_ij/100))

So three separate insiders buying compounds toward 100, while the same insider
filing three amendments does not — because deduplication by actor happens
first, and the three amendments are one actor.

**Determinism.** Floating-point multiplication is not associative, so the same
set of sub-signals folded in a different order can differ in the last bits.
Set and dict iteration order is not guaranteed to be stable across the values
involved here, so every reduction sorts its inputs by a stable key before
folding. Without that, the byte-identical rerun required by Phase 3
criterion 1 fails intermittently — which is the worst way for it to fail.
"""

from __future__ import annotations

from dataclasses import dataclass

#: Scores are stored at this precision. Rounding at the boundary keeps a
#: last-bit difference from propagating into an exported CSV.
SCORE_PRECISION = 6


@dataclass(frozen=True, slots=True)
class SubSignal:
    """One piece of evidence within a category.

    ``actor_key`` is the deduplication key — the person or institution whose
    decision this was. Two sub-signals with the same actor are one actor's
    view, however many documents they filed.
    """

    actor_key: str
    score: float
    feature_key: str
    detail: str = ""

    def __post_init__(self) -> None:
        if not 0.0 <= self.score <= 100.0:
            raise ValueError(
                f"Sub-signal {self.feature_key!r} scored {self.score}, outside 0-100. "
                f"Normalization must clamp before combination."
            )


def deduplicate_by_actor(signals: list[SubSignal]) -> list[SubSignal]:
    """Keep the strongest sub-signal per actor.

    SPEC §6.3: "three separate insiders buying compounds; the same insider
    filing three amended forms does not". Taking the max rather than summing
    means an actor who acts twice counts once, at their strongest.

    Sorted output, so downstream folding is order-stable.
    """
    strongest: dict[str, SubSignal] = {}
    for signal in signals:
        current = strongest.get(signal.actor_key)
        if current is None or signal.score > current.score:
            strongest[signal.actor_key] = signal
        elif signal.score == current.score and signal.feature_key < current.feature_key:
            # Deterministic tie-break: without this, which of two equal-scoring
            # signals survives depends on input order.
            strongest[signal.actor_key] = signal
    return sorted(strongest.values(), key=lambda s: (s.actor_key, s.feature_key))


def combine_category(signals: list[SubSignal]) -> float:
    """Diminishing-returns combination across independent actors.

    Returns 0.0 for an empty category — which means "no evidence", and is
    distinct from a low score meaning "weak evidence". The caller decides
    whether the category is unavailable; this function only does arithmetic.
    """
    deduplicated = deduplicate_by_actor(signals)
    if not deduplicated:
        return 0.0

    remaining = 1.0
    for signal in deduplicated:
        remaining *= 1.0 - (signal.score / 100.0)
    return round(100.0 * (1.0 - remaining), SCORE_PRECISION)


def independent_actor_count(signals: list[SubSignal]) -> int:
    """How many distinct actors contributed. Drives cluster detection."""
    return len({signal.actor_key for signal in signals})
