"""Top signals and per-company convergence. docs/API_CONTRACT.md.

Two fields here are deliberately different numbers and the UI must not conflate
them (API_CONTRACT is explicit about it):

* ``axes`` — the six radar dimensions;
* ``categories_cleared`` — how many of the *ten* evidence buckets cleared τ.

The count ring renders the second. A 94 backed by one category and a 94 backed
by five must not look alike, which is the whole of UI_SPEC correction #7.

``contradiction`` is always present, even at zero (correction #8), and carries
the count of checks that could actually run — a contradiction score computed
from 3 of 13 checks is a different claim from one computed from 13 of 13.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import select

from imt.api.deps import SessionDep, source_states
from imt.api.envelope import Coverage, Envelope, Meta
from imt.core.clock import utc_now
from imt.db.enums import CATEGORY_LABELS, SignalCategory
from imt.db.models import Company, ContradictionItem, Score, TickerMapRow

router = APIRouter(tags=["signals"])

#: The six radar dimensions (UI_SPEC §4.5). A subset of the ten buckets.
RADAR_AXES: tuple[SignalCategory, ...] = (
    SignalCategory.CORPORATE_INSIDER,
    SignalCategory.POLITICAL,
    SignalCategory.INSTITUTIONAL,
    SignalCategory.CORPORATE_EVENT,
    SignalCategory.FUNDAMENTAL,
    SignalCategory.MACRO_SECTOR,
)


class ScoreProvenance(BaseModel):
    normalization: str
    weights_version: str
    as_of: date
    validated: bool
    #: How many contradiction checks could run. Rendered next to the score so
    #: a low-coverage score cannot pass as a thorough one.
    contradiction_checks_available: int
    contradiction_checks_total: int


class Driver(BaseModel):
    category: str
    score: float
    label: str


class TopSignal(BaseModel):
    rank: int
    cik: str
    ticker: str | None
    company_name: str
    research_priority: float
    confidence: float
    contradiction: float
    convergence: float
    categories_cleared: int
    categories_total: int
    top_drivers: list[Driver]
    score_provenance: ScoreProvenance


class Axis(BaseModel):
    category: str
    label: str
    score: float
    cleared: bool


class ContradictionEntry(BaseModel):
    check: str
    status: str
    severity: float
    detail: str | None
    source_url: str | None


class ContradictionBlock(BaseModel):
    score: float
    checks_available: int
    checks_total: int
    items: list[ContradictionEntry]


class ConvergenceView(BaseModel):
    research_priority: float
    confidence: float
    axes: list[Axis]
    categories_cleared: int
    categories_total: int
    convergence: float
    convergence_tau: float
    contradiction: ContradictionBlock
    freshness: float
    data_quality: float
    score_provenance: ScoreProvenance


def _provenance(score: Score, available: int, total: int) -> ScoreProvenance:
    return ScoreProvenance(
        normalization=score.normalization.value,
        weights_version=score.weights_version,
        as_of=score.as_of,
        # False for the whole of V1: weights are unvalidated until Phase 8.
        validated=score.normalization.value == "percentile",
        contradiction_checks_available=available,
        contradiction_checks_total=total,
    )


def _check_counts(session: SessionDep, cik: str, as_of: date) -> tuple[int, int]:
    rows = (
        session.execute(
            select(ContradictionItem.status).where(
                ContradictionItem.cik == cik, ContradictionItem.as_of == as_of
            )
        )
        .scalars()
        .all()
    )
    total = len(rows)
    available = sum(1 for status in rows if status.value != "unavailable")
    return available, total


@router.get("/signals/top", response_model=Envelope[list[TopSignal]])
def top_signals(
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 5,
) -> Envelope[list[TopSignal]]:
    latest = session.execute(
        select(Score.as_of).order_by(Score.as_of.desc()).limit(1)
    ).scalar_one_or_none()
    if latest is None:
        return Envelope(
            data=[],
            meta=Meta(generated_at=utc_now(), sources=source_states(session)),
        )

    rows = session.execute(
        select(Score, Company.name)
        .join(Company, Company.cik == Score.cik)
        .where(Score.as_of == latest)
        .order_by(Score.research_priority.desc(), Score.cik)
        .limit(limit)
    ).all()

    signals: list[TopSignal] = []
    for rank, (score, company_name) in enumerate(rows, start=1):
        available, total = _check_counts(session, score.cik, score.as_of)
        drivers = sorted(score.category_scores.items(), key=lambda kv: (-kv[1], kv[0]))[:4]
        ticker = session.execute(
            select(TickerMapRow.ticker)
            .where(
                TickerMapRow.cik == score.cik,
                TickerMapRow.valid_from <= score.as_of,
                (TickerMapRow.valid_to.is_(None)) | (TickerMapRow.valid_to >= score.as_of),
            )
            .limit(1)
        ).scalar_one_or_none()

        signals.append(
            TopSignal(
                rank=rank,
                cik=score.cik,
                ticker=ticker,
                company_name=company_name,
                research_priority=float(score.research_priority),
                confidence=float(score.confidence),
                contradiction=float(score.contradiction),
                convergence=float(score.convergence),
                categories_cleared=score.categories_cleared,
                categories_total=score.categories_total,
                top_drivers=[
                    Driver(
                        category=name,
                        score=float(value),
                        label=CATEGORY_LABELS[SignalCategory(name)],
                    )
                    for name, value in drivers
                ],
                score_provenance=_provenance(score, available, total),
            )
        )

    return Envelope(
        data=signals,
        meta=Meta(
            as_of=latest,
            generated_at=utc_now(),
            sources=source_states(session),
            weights_version=rows[0][0].weights_version if rows else None,
            normalization=rows[0][0].normalization.value if rows else None,
        ),
    )


@router.get("/companies/{cik}/convergence", response_model=Envelope[ConvergenceView | None])
def convergence(session: SessionDep, cik: str) -> Envelope[ConvergenceView | None]:
    score = session.execute(
        select(Score).where(Score.cik == cik).order_by(Score.as_of.desc()).limit(1)
    ).scalar_one_or_none()

    if score is None:
        return Envelope(
            data=None, meta=Meta(generated_at=utc_now(), sources=source_states(session))
        )

    items = (
        session.execute(
            select(ContradictionItem)
            .where(ContradictionItem.cik == cik, ContradictionItem.as_of == score.as_of)
            .order_by(ContradictionItem.check_id)
        )
        .scalars()
        .all()
    )
    available = sum(1 for i in items if i.status.value != "unavailable")

    view = ConvergenceView(
        research_priority=float(score.research_priority),
        confidence=float(score.confidence),
        axes=[
            Axis(
                category=axis.value,
                label=CATEGORY_LABELS[axis],
                score=float(score.category_scores.get(axis.value, 0.0)),
                cleared=float(score.category_scores.get(axis.value, 0.0)) >= 60.0,
            )
            for axis in RADAR_AXES
        ],
        # Deliberately NOT len(axes): this counts across all ten buckets and
        # is what the count ring renders.
        categories_cleared=score.categories_cleared,
        categories_total=score.categories_total,
        convergence=float(score.convergence),
        convergence_tau=60.0,
        contradiction=ContradictionBlock(
            score=float(score.contradiction),
            checks_available=available,
            checks_total=len(items),
            items=[
                ContradictionEntry(
                    check=i.check_id,
                    status=i.status.value,
                    severity=float(i.severity),
                    detail=i.detail,
                    source_url=i.source_url,
                )
                for i in items
            ],
        ),
        freshness=float(score.freshness),
        data_quality=float(score.data_quality),
        score_provenance=_provenance(score, available, len(items)),
    )

    return Envelope(
        data=view,
        meta=Meta(
            as_of=score.as_of,
            generated_at=utc_now(),
            data_quality=int(float(score.data_quality)),
            sources=source_states(session),
            weights_version=score.weights_version,
            normalization=score.normalization.value,
            coverage=Coverage(
                categories_available=score.categories_cleared,
                categories_total=score.categories_total,
            ),
        ),
    )
