"""Insider features and cluster detection. SPEC §8.

**Cluster detection is the flagship signal**: ≥3 *independent* insiders filing
open-market purchases within a rolling 7-day window, weighted higher when a
CEO or CFO participates.

Two ways to get this wrong, both of which manufacture a cluster from nothing:

* **Counting documents instead of people.** One officer filing three
  amendments is one person's decision. Deduplication happens on ``actor_key``,
  which the Form 4 parser builds from every reporting owner on the filing, so
  a joint filing by an officer and their family trust is also one actor.
* **Counting compensation as conviction.** Only code ``P`` counts. A grant
  (``A``), an option exercise (``M``) and tax withholding (``F``) are
  mechanical events on a vesting schedule; a cluster of them means the
  vesting date arrived, not that anyone decided anything.

Nothing here reads the clock — ``as_of`` is an argument (SPEC §7.5).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

CLUSTER_WINDOW_DAYS = 7
CLUSTER_MIN_ACTORS = 3

#: Role ranking. CEO/CFO outrank other officers, who outrank directors and
#: 10% holders (SPEC §8). Used both for weighting and by the CEO/CFO-selling
#: contradiction check.
ROLE_RANK: dict[str, int] = {"ceo_cfo": 3, "officer": 2, "director": 1, "ten_percent": 1}

_SENIOR_TITLES = (
    "chief executive",
    "chief financial",
    "ceo",
    "cfo",
    "president and chief",
)


@dataclass(frozen=True, slots=True)
class InsiderPurchase:
    actor_key: str
    insider_name: str
    role: str | None
    is_officer: bool
    is_director: bool
    is_ten_percent_owner: bool
    transaction_date: date
    value_minor: int | None
    is_10b5_1: bool | None
    source_url: str = ""

    @property
    def role_rank(self) -> int:
        if is_senior_officer(self.role):
            return ROLE_RANK["ceo_cfo"]
        if self.is_officer:
            return ROLE_RANK["officer"]
        if self.is_director:
            return ROLE_RANK["director"]
        if self.is_ten_percent_owner:
            return ROLE_RANK["ten_percent"]
        return 0


@dataclass(frozen=True, slots=True)
class ClusterResult:
    detected: bool
    actor_count: int
    window_start: date | None
    window_end: date | None
    includes_senior_officer: bool
    total_value_minor: int
    actors: tuple[str, ...] = ()


def is_senior_officer(role: str | None) -> bool:
    """CEO or CFO, from the free-text officer title on the filing.

    Titles are prose ("Executive Vice President and Chief Financial Officer"),
    so this is substring matching. It is deliberately narrow: over-matching
    would inflate every cluster's weight, and a missed CFO costs one
    increment rather than fabricating one.
    """
    if not role:
        return False
    lowered = role.lower()
    return any(marker in lowered for marker in _SENIOR_TITLES)


def discretionary_purchases(purchases: list[InsiderPurchase]) -> list[InsiderPurchase]:
    """Exclude purchases made under a pre-existing 10b5-1 plan.

    The decision was made when the plan was adopted, often months earlier, so
    the execution is not evidence about today. Where the filing does not say
    (``is_10b5_1 is None``, which is most pre-2023 filings) the purchase is
    kept — absence of a disclosure is not a disclosure of absence, and
    dropping them would silently discard most of the historical corpus.
    """
    return [p for p in purchases if p.is_10b5_1 is not True]


def detect_cluster(
    purchases: list[InsiderPurchase],
    *,
    as_of: date,
    lookback_days: int = 90,
) -> ClusterResult:
    """Find the strongest rolling window of independent purchases.

    Sliding window over transaction dates, sorted first so the result does not
    depend on input order. Returns the window with the most distinct actors,
    tie-broken by total value.
    """
    window_start_bound = as_of - timedelta(days=lookback_days)
    candidates = sorted(
        (
            p
            for p in discretionary_purchases(purchases)
            if window_start_bound <= p.transaction_date <= as_of
        ),
        key=lambda p: (p.transaction_date, p.actor_key),
    )

    if not candidates:
        return ClusterResult(False, 0, None, None, False, 0)

    best = ClusterResult(False, 0, None, None, False, 0)

    for i, anchor in enumerate(candidates):
        window_end = anchor.transaction_date + timedelta(days=CLUSTER_WINDOW_DAYS - 1)
        window = [p for p in candidates[i:] if p.transaction_date <= window_end]

        actors = sorted({p.actor_key for p in window})
        if len(actors) < len(best.actors) or not actors:
            continue

        total = sum(p.value_minor or 0 for p in window)
        if len(actors) == len(best.actors) and total <= best.total_value_minor:
            continue

        best = ClusterResult(
            detected=len(actors) >= CLUSTER_MIN_ACTORS,
            actor_count=len(actors),
            window_start=anchor.transaction_date,
            window_end=min(window_end, max(p.transaction_date for p in window)),
            includes_senior_officer=any(p.role_rank == ROLE_RANK["ceo_cfo"] for p in window),
            total_value_minor=total,
            actors=tuple(actors),
        )

    return best


def cluster_strength(cluster: ClusterResult) -> float:
    """Raw cluster feature, before normalization.

    Senior-officer participation is a multiplier rather than an additive bonus
    because SPEC §8 says a CEO or CFO in a cluster scores "materially higher
    than any isolated transaction" — the point is the interaction, not a
    constant.
    """
    if not cluster.detected:
        return float(cluster.actor_count)
    return float(cluster.actor_count) * (1.5 if cluster.includes_senior_officer else 1.0)
