"""``imt score run`` — assemble facts, score, persist.

The database work lives here so ``runner.score_company`` can stay pure. The
split matters: everything that could make a rerun differ (queries, the clock,
iteration order) is on this side of the boundary, and the scoring itself takes
only a materialized fact set.

**Look-ahead is answered once, here.** The fact query filters on
``public_available_at <= as_of``, so a backtest and a live run take the same
path. No scorer has to remember to check.
"""

from __future__ import annotations

import csv
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime, time
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from imt.core.clock import MARKET_TZ
from imt.db.enums import ContradictionStatus, NormalizationMethod, SignalCategory
from imt.db.models import Company, ContradictionItem, Score, SignalEvent
from imt.features.insider import InsiderPurchase, cluster_strength, detect_cluster
from imt.scoring.categories import SubSignal
from imt.scoring.freshness import freshness as compute_freshness
from imt.scoring.normalize import normalize
from imt.scoring.runner import FactSet, ScoreRow, score_company
from imt.scoring.weights import Weights

#: Datasets ingested so far. Gates which contradiction checks may run; each
#: phase adds to it as its ingest lands (docs/ARCHITECTURE.md §E).
AVAILABLE_DATA_BY_PHASE: dict[str, frozenset[str]] = {
    "phase2": frozenset({"insider_transactions", "filings_8k"}),
}


@dataclass(frozen=True, slots=True)
class ScoreJobResult:
    as_of: date
    companies_scored: int
    weights_version: str

    def summary(self) -> str:
        return (
            f"scored {self.companies_scored} companies as of {self.as_of} "
            f"with weights {self.weights_version}"
        )


def _cutoff(as_of: date) -> datetime:
    """Everything public by the end of the as-of date.

    A filing accepted at 09:00 on the as-of date is in; one accepted the next
    morning is not, however tempting it is to include a whole extra day of
    evidence.
    """
    return datetime.combine(as_of, time(23, 59, 59), tzinfo=MARKET_TZ)


def _events_for(session: Session, cik: str, as_of: date) -> Sequence[SignalEvent]:
    return (
        session.execute(
            select(SignalEvent)
            .where(
                SignalEvent.cik == cik,
                # The only look-ahead gate in the system.
                SignalEvent.public_available_at <= _cutoff(as_of),
            )
            .order_by(SignalEvent.event_id)
        )
        .scalars()
        .all()
    )


def build_fact_set(
    session: Session, cik: str, as_of: date, weights: Weights, *, available_data: frozenset[str]
) -> FactSet:
    """Materialize everything known about one company as of one date."""
    events = _events_for(session, cik, as_of)

    signals: dict[SignalCategory, list[SubSignal]] = {}
    underlying: dict[SignalCategory, set[str]] = {}
    purchases: list[InsiderPurchase] = []
    sales: list[dict[str, object]] = []

    for event in events:
        category = event.category
        if event.underlying_event_key:
            underlying.setdefault(category, set()).add(event.underlying_event_key)

        if category is SignalCategory.CORPORATE_INSIDER:
            _collect_insider(event, purchases, sales)

    cluster = detect_cluster(purchases, as_of=as_of)
    if purchases:
        strength = normalize("insider_cluster_size", cluster_strength(cluster), weights)
        if strength is not None:
            signals[SignalCategory.CORPORATE_INSIDER] = [
                SubSignal(
                    actor_key=actor,
                    score=strength.score,
                    feature_key="insider_cluster_size",
                )
                for actor in (cluster.actors or ("none",))
            ]

    # Categories with no events at all are unavailable, which is different
    # from a category that was examined and scored zero.
    seen = {event.category for event in events}
    unavailable = frozenset(c for c in SignalCategory if c not in seen)

    return FactSet(
        cik=cik,
        as_of=as_of,
        category_signals=signals,
        unavailable_categories=unavailable,
        underlying_event_keys={k: frozenset(v) for k, v in underlying.items()},
        contradiction_facts={"insider_sales": sales, "insider_purchases": []},
        available_data=available_data,
        feed_health=100.0,
        normalization=NormalizationMethod.FALLBACK_THRESHOLD,
    )


def _collect_insider(
    event: SignalEvent, purchases: list[InsiderPurchase], sales: list[dict[str, object]]
) -> None:
    """Split an insider event into purchase and sale evidence.

    The headline carries the transaction code's description, which is enough
    to route it; the typed row is consulted for the numbers.
    """
    headline = event.headline.lower()
    if "open-market purchase" in headline:
        purchases.append(
            InsiderPurchase(
                actor_key=event.actor_key or event.event_id,
                insider_name=event.headline,
                role=event.headline.split("—")[0].strip(),
                is_officer="officer" in headline or "chief" in headline,
                is_director="director" in headline,
                is_ten_percent_owner="10%" in headline,
                transaction_date=event.transaction_date or event.effective_date,
                value_minor=event.value_exact_minor,
                is_10b5_1=None,
                source_url=event.source_document_url,
            )
        )
    elif "open-market sale" in headline:
        sales.append(
            {
                "role_rank": 3 if "chief" in headline else 1,
                "transaction_code": "S",
                "value_minor": event.value_exact_minor,
                "date": (event.transaction_date or event.effective_date).isoformat(),
                "role": event.headline.split("—")[0].strip(),
                "source_url": event.source_document_url,
            }
        )


def persist(session: Session, row: ScoreRow) -> None:
    """Write the score and its contradiction detail.

    ``weights_version`` and ``normalization`` are NOT NULL columns fed from the
    row, which itself took them from the loaded weights — so a score cannot
    reach the database without its provenance.
    """
    session.execute(
        pg_insert(Score)
        .values(
            cik=row.cik,
            as_of=row.as_of,
            research_priority=row.research_priority,
            confidence=row.confidence,
            convergence=row.convergence,
            contradiction=row.contradiction,
            freshness=row.freshness,
            data_quality=row.data_quality,
            base=row.base,
            category_scores=row.category_scores,
            categories_cleared=row.categories_cleared,
            categories_total=row.categories_total,
            weights_version=row.weights_version,
            normalization=row.normalization,
            weights_hash=row.weights_hash,
        )
        .on_conflict_do_update(
            index_elements=[Score.cik, Score.as_of],
            set_={
                "research_priority": row.research_priority,
                "confidence": row.confidence,
                "convergence": row.convergence,
                "contradiction": row.contradiction,
                "freshness": row.freshness,
                "data_quality": row.data_quality,
                "base": row.base,
                "category_scores": row.category_scores,
                "categories_cleared": row.categories_cleared,
                "categories_total": row.categories_total,
                "weights_version": row.weights_version,
                "normalization": row.normalization,
                "weights_hash": row.weights_hash,
            },
        )
    )

    # Rewritten wholesale: a check that stopped firing must disappear, not
    # linger as a stale contradiction against a company that no longer has it.
    session.execute(
        delete(ContradictionItem).where(
            ContradictionItem.cik == row.cik, ContradictionItem.as_of == row.as_of
        )
    )
    for outcome in row.contradiction_detail.outcomes:
        session.add(
            ContradictionItem(
                cik=row.cik,
                as_of=row.as_of,
                check_id=outcome.check_id,
                status=ContradictionStatus(outcome.status),
                severity=outcome.severity,
                detail=outcome.detail,
                source_url=outcome.source_url,
            )
        )


def run(
    session: Session,
    *,
    as_of: date,
    weights: Weights,
    available_data: frozenset[str] | None = None,
    export_to: Path | None = None,
) -> ScoreJobResult:
    """Score every company with at least one event available by ``as_of``."""
    data = available_data or AVAILABLE_DATA_BY_PHASE["phase2"]

    ciks = (
        session.execute(
            select(Company.cik)
            .join(SignalEvent, SignalEvent.cik == Company.cik)
            .where(SignalEvent.public_available_at <= _cutoff(as_of))
            .distinct()
            .order_by(Company.cik)
        )
        .scalars()
        .all()
    )

    rows: list[ScoreRow] = []
    for cik in ciks:
        facts = build_fact_set(session, cik, as_of, weights, available_data=data)
        events = _events_for(session, cik, as_of)
        freshness_value = max(
            (
                compute_freshness(
                    "form4_purchase",
                    as_of=as_of,
                    transaction_date=e.transaction_date or e.effective_date,
                    disclosure_date=e.disclosure_date,
                    weights=weights,
                )
                for e in events
            ),
            default=0.0,
        )
        row = score_company(cik, as_of, weights, facts, freshness=freshness_value)
        persist(session, row)
        rows.append(row)

    session.commit()

    if export_to is not None:
        export(rows, export_to)

    return ScoreJobResult(as_of=as_of, companies_scored=len(rows), weights_version=weights.version)


def export(rows: list[ScoreRow], path: Path) -> None:
    """Deterministic CSV. Phase 3 criterion 1 compares these byte for byte.

    Rows sorted by CIK and floats pre-formatted to fixed precision — an
    unrounded float would make two identical runs differ in the last digit.
    """
    ordered = sorted(rows, key=lambda r: r.cik)
    if not ordered:
        path.write_text("", encoding="utf-8")
        return
    exported = [row.to_export_row() for row in ordered]
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(exported[0].keys()), lineterminator="\n")
        writer.writeheader()
        writer.writerows(exported)
