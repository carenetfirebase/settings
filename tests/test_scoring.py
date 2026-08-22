"""Scoring core. docs/PHASES.md Phase 3.

``TestCoreCorrectness`` is the one that matters. If five signals from a single
source can score like five signals from five independent sources, the product
has no thesis — everything else here is bookkeeping by comparison.
"""

from __future__ import annotations

import ast
from datetime import date
from pathlib import Path
from typing import ClassVar

import pytest

from imt.db.enums import ContradictionStatus, NormalizationMethod, SignalCategory
from imt.features.insider import (
    InsiderPurchase,
    detect_cluster,
    discretionary_purchases,
    is_senior_officer,
)
from imt.scoring import load_weights
from imt.scoring.categories import SubSignal, combine_category, deduplicate_by_actor
from imt.scoring.composite import V1_CONFIDENCE_CAP, compute_composites
from imt.scoring.contradiction import evaluate
from imt.scoring.convergence import CategoryScore, compute_convergence
from imt.scoring.freshness import freshness
from imt.scoring.normalize import interpolate, normalize, percentile_rank
from imt.scoring.runner import FactSet, score_company

WEIGHTS = load_weights()
AS_OF = date(2026, 6, 1)

ALL_DATA = frozenset(
    {
        "insider_transactions",
        "filings_8k",
        "prices_daily",
        "congressional_transactions",
        "xbrl_facts",
        "short_interest",
        "government_contracts",
    }
)


def signals(category: str, n: int, strength: float = 100.0) -> list[SubSignal]:
    """``n`` independent actors in one category, each at ``strength``."""
    return [
        SubSignal(actor_key=f"{category}-actor-{i}", score=strength, feature_key=f"{category}_{i}")
        for i in range(n)
    ]


class TestCoreCorrectness:
    """Phase 3 criterion 2 — the premise of the entire product.

    Sub-signal strengths are pinned, because the thresholds depend on them:
    five *moderate* signals across five categories would score 77, not 80, and
    a test that did not say so would fail for a reason that looks like a bug
    in the formula.
    """

    def test_five_signals_from_one_category_score_below_45(self) -> None:
        """One loud source is not convergence, however loud."""
        facts = FactSet(
            cik="0000000001",
            as_of=AS_OF,
            category_signals={SignalCategory.CORPORATE_INSIDER: signals("insider", 5, 100.0)},
            available_data=ALL_DATA,
        )
        row = score_company("0000000001", AS_OF, WEIGHTS, facts)
        assert row.convergence < 45, (
            f"Five Form 4 signals scored Convergence {row.convergence:.1f}. "
            f"A single category must never look like convergence."
        )
        assert row.categories_cleared == 1

    def test_one_signal_each_from_five_categories_scores_above_80(self) -> None:
        """Five independent categories agreeing is what the product is for."""
        five = [
            SignalCategory.CORPORATE_INSIDER,
            SignalCategory.POLITICAL,
            SignalCategory.INSTITUTIONAL,
            SignalCategory.GOVERNMENT,
            SignalCategory.CORPORATE_EVENT,
        ]
        facts = FactSet(
            cik="0000000002",
            as_of=AS_OF,
            category_signals={c: signals(c.value, 1, 100.0) for c in five},
            available_data=ALL_DATA,
        )
        row = score_company("0000000002", AS_OF, WEIGHTS, facts)
        assert row.convergence > 80, (
            f"Five independent categories scored Convergence {row.convergence:.1f}"
        )
        assert row.categories_cleared == 5

    def test_the_gap_between_them_is_large(self) -> None:
        """Not just either side of a threshold — a wide, obvious separation."""
        one = score_company(
            "1",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="1",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: signals("i", 5, 100.0)},
                available_data=ALL_DATA,
            ),
        )
        five = [
            SignalCategory.CORPORATE_INSIDER,
            SignalCategory.POLITICAL,
            SignalCategory.INSTITUTIONAL,
            SignalCategory.GOVERNMENT,
            SignalCategory.CORPORATE_EVENT,
        ]
        many = score_company(
            "2",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="2",
                as_of=AS_OF,
                category_signals={c: signals(c.value, 1, 100.0) for c in five},
                available_data=ALL_DATA,
            ),
        )
        assert many.convergence - one.convergence > 40


class TestReproducibility:
    """Phase 3 criterion 1: byte-identical reruns."""

    def _facts(self) -> FactSet:
        return FactSet(
            cik="0000000003",
            as_of=AS_OF,
            category_signals={
                SignalCategory.CORPORATE_INSIDER: signals("insider", 4, 82.5),
                SignalCategory.POLITICAL: signals("political", 2, 61.25),
                SignalCategory.GOVERNMENT: signals("gov", 3, 73.125),
            },
            contradiction_facts={
                "insider_sales": [
                    {
                        "role_rank": 3,
                        "transaction_code": "S",
                        "value_minor": 110_000_00,
                        "date": "2026-05-04",
                        "role": "Chief Financial Officer",
                    }
                ]
            },
            available_data=ALL_DATA,
        )

    def test_two_runs_export_identically(self) -> None:
        first = score_company("0000000003", AS_OF, WEIGHTS, self._facts()).to_export_row()
        second = score_company("0000000003", AS_OF, WEIGHTS, self._facts()).to_export_row()
        assert first == second

    def test_signal_order_does_not_change_the_score(self) -> None:
        """Float multiplication is not associative.

        Without sorting before every reduction this passes most of the time
        and fails occasionally, which is the worst possible failure mode for a
        reproducibility guarantee.
        """
        forward = signals("insider", 5, 77.0)
        row_a = score_company(
            "x",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="x",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: forward},
                available_data=ALL_DATA,
            ),
        )
        row_b = score_company(
            "x",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="x",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: list(reversed(forward))},
                available_data=ALL_DATA,
            ),
        )
        assert row_a.to_export_row() == row_b.to_export_row()


class TestNoClockInScoring:
    """Phase 3 criterion 3, at the AST level."""

    FORBIDDEN: ClassVar[set[str]] = {"now", "today", "time", "utcnow"}

    def test_no_scoring_module_reads_the_clock(self) -> None:
        offenders: list[str] = []
        root = Path(__file__).resolve().parents[1] / "src" / "imt" / "scoring"
        for path in sorted(root.rglob("*.py")):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                    if node.func.attr in self.FORBIDDEN:
                        offenders.append(f"{path.name}:{node.lineno} → .{node.func.attr}()")
        assert offenders == [], "Scoring must take as_of as an argument (SPEC §7.5):\n" + "\n".join(
            offenders
        )

    def test_features_package_is_also_clean(self) -> None:
        offenders: list[str] = []
        root = Path(__file__).resolve().parents[1] / "src" / "imt" / "features"
        for path in sorted(root.rglob("*.py")):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                    if node.func.attr in self.FORBIDDEN:
                        offenders.append(f"{path.name}:{node.lineno}")
        assert offenders == []


class TestClusterDetection:
    """Phase 3 criterion 4."""

    def purchase(
        self, actor: str, day: int, *, role: str | None = None, plan: bool | None = None
    ) -> InsiderPurchase:
        return InsiderPurchase(
            actor_key=actor,
            insider_name=actor,
            role=role,
            is_officer=role is not None,
            is_director=False,
            is_ten_percent_owner=False,
            transaction_date=date(2026, 5, day),
            value_minor=100_000_00,
            is_10b5_1=plan,
        )

    def test_fires_on_three_independent_filers_within_seven_days(self) -> None:
        cluster = detect_cluster(
            [
                self.purchase("a", 10, role="Chief Executive Officer"),
                self.purchase("b", 12),
                self.purchase("c", 15),
            ],
            as_of=AS_OF,
        )
        assert cluster.detected
        assert cluster.actor_count == 3
        assert cluster.includes_senior_officer

    def test_does_not_fire_on_one_filer_with_three_amendments(self) -> None:
        """Three documents, one decision.

        The parser gives all three the same actor_key, so this is a test that
        the whole chain from parsing to detection counts people, not filings.
        """
        cluster = detect_cluster(
            [self.purchase("a", 10), self.purchase("a", 11), self.purchase("a", 12)],
            as_of=AS_OF,
        )
        assert not cluster.detected
        assert cluster.actor_count == 1

    def test_does_not_fire_when_purchases_straddle_the_window(self) -> None:
        cluster = detect_cluster(
            [self.purchase("a", 1), self.purchase("b", 12), self.purchase("c", 25)],
            as_of=AS_OF,
        )
        assert not cluster.detected

    def test_10b5_1_purchases_are_excluded(self) -> None:
        """The decision was made when the plan was adopted, months earlier."""
        kept = discretionary_purchases(
            [
                self.purchase("a", 10, plan=True),
                self.purchase("b", 11, plan=False),
                self.purchase("c", 12, plan=None),
            ]
        )
        assert {p.actor_key for p in kept} == {"b", "c"}

    def test_unknown_plan_status_is_kept(self) -> None:
        """Absence of a disclosure is not a disclosure of absence.

        Most pre-2023 filings say nothing; dropping them would silently
        discard most of the historical corpus.
        """
        cluster = detect_cluster(
            [self.purchase(a, 10 + i) for i, a in enumerate("abc")], as_of=AS_OF
        )
        assert cluster.detected

    @pytest.mark.parametrize(
        ("title", "expected"),
        [
            ("Chief Executive Officer", True),
            ("EVP and Chief Financial Officer", True),
            ("CFO", True),
            ("Chief Marketing Officer", False),
            ("Director", False),
            (None, False),
        ],
    )
    def test_senior_officer_detection(self, title: str | None, expected: bool) -> None:
        assert is_senior_officer(title) is expected


class TestContradiction:
    """Phase 3 criterion 6, plus the registry from ARCHITECTURE §E."""

    def test_unavailable_is_never_reported_as_clear(self) -> None:
        """The whole reason the registry exists.

        A zero in a column headed "Contradiction" claims the system searched
        and found nothing. With no data ingested it has searched nothing.
        """
        result = evaluate({}, AS_OF, WEIGHTS, available_data=frozenset())
        assert result.score == 0.0
        assert all(o.status is ContradictionStatus.UNAVAILABLE for o in result.outcomes)
        assert result.checks_available == 0
        assert result.coverage == 0.0

    def test_partial_coverage_is_reported_honestly(self) -> None:
        result = evaluate(
            {}, AS_OF, WEIGHTS, available_data=frozenset({"insider_transactions", "filings_8k"})
        )
        assert 0 < result.checks_available < result.checks_total
        assert 0 < result.coverage < 1

    def test_unavailable_checks_reduce_data_quality(self) -> None:
        """Which keeps the least-examined companies out of the top ranks."""
        thin = score_company(
            "1",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="1",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: signals("i", 3, 90.0)},
                available_data=frozenset({"insider_transactions"}),
            ),
        )
        full = score_company(
            "1",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="1",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: signals("i", 3, 90.0)},
                available_data=ALL_DATA,
            ),
        )
        assert thin.data_quality < full.data_quality
        assert thin.research_priority < full.research_priority

    def test_ceo_selling_fires(self) -> None:
        result = evaluate(
            {
                "insider_sales": [
                    {
                        "role_rank": 3,
                        "transaction_code": "S",
                        "value_minor": 110_000_00,
                        "date": "2026-05-04",
                        "role": "Chief Financial Officer",
                    }
                ]
            },
            AS_OF,
            WEIGHTS,
            available_data=ALL_DATA,
        )
        fired = {o.check_id for o in result.fired}
        assert "ceo_cfo_selling" in fired
        assert result.score > 0

    def test_tax_withholding_is_not_selling(self) -> None:
        """Code F is mechanical withholding on a vesting grant, not a decision.

        Without this the check fires on every routine vesting event.
        """
        result = evaluate(
            {
                "insider_sales": [
                    {"role_rank": 3, "transaction_code": "F", "value_minor": 90_000_00}
                ]
            },
            AS_OF,
            WEIGHTS,
            available_data=ALL_DATA,
        )
        assert "ceo_cfo_selling" not in {o.check_id for o in result.fired}

    def test_contradiction_100_reduces_priority_to_exactly_40_percent(self) -> None:
        """Phase 3 criterion 6, with the other multipliers pinned at 100.

        Contradiction is injected rather than derived: 100·(1−Π(1−c/100))
        cannot reach 100 unless a single check returns exactly 100, so the
        criterion is unreachable from check inputs.
        """
        category_scores = [
            CategoryScore(category=c, score=100.0, actor_count=1) for c in SignalCategory
        ]
        clean = compute_composites(
            category_scores,
            convergence=100.0,
            contradiction=0.0,
            data_quality=100.0,
            category_coverage=1.0,
            normalization=NormalizationMethod.PERCENTILE,
            weights=WEIGHTS,
        )
        contradicted = compute_composites(
            category_scores,
            convergence=100.0,
            contradiction=100.0,
            data_quality=100.0,
            category_coverage=1.0,
            normalization=NormalizationMethod.PERCENTILE,
            weights=WEIGHTS,
        )
        assert contradicted.research_priority == pytest.approx(
            clean.research_priority * 0.4, rel=1e-9
        )

    def test_contradiction_is_never_netted_into_the_score(self) -> None:
        """It multiplies and is reported separately (SPEC §6.6)."""
        row = score_company(
            "1",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="1",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: signals("i", 3, 90.0)},
                contradiction_facts={
                    "insider_sales": [
                        {"role_rank": 3, "transaction_code": "S", "value_minor": 5_000_00}
                    ]
                },
                available_data=ALL_DATA,
            ),
        )
        assert row.contradiction > 0
        assert row.research_priority > 0  # reduced, not cancelled


class TestCrossCategoryDeduplication:
    """ARCHITECTURE §I — not in the spec, found in Phase 0.

    An 8-K announcing a contract award and the USAspending record of that same
    award are two categories by SPEC §6.3 and one event in reality.
    """

    def test_shared_underlying_event_counts_once(self) -> None:
        shared = frozenset({"award-2026-0042"})
        scores = [
            CategoryScore(SignalCategory.GOVERNMENT, 90.0, 1, shared),
            CategoryScore(SignalCategory.CORPORATE_EVENT, 85.0, 1, shared),
        ]
        result = compute_convergence(scores, WEIGHTS)
        assert result.categories_cleared == 1
        assert SignalCategory.CORPORATE_EVENT in result.suppressed_as_duplicate

    def test_independent_events_both_count(self) -> None:
        scores = [
            CategoryScore(SignalCategory.GOVERNMENT, 90.0, 1, frozenset({"award-1"})),
            CategoryScore(SignalCategory.CORPORATE_EVENT, 85.0, 1, frozenset({"merger-2"})),
        ]
        assert compute_convergence(scores, WEIGHTS).categories_cleared == 2

    def test_the_stronger_category_survives(self) -> None:
        shared = frozenset({"e1"})
        result = compute_convergence(
            [
                CategoryScore(SignalCategory.GOVERNMENT, 70.0, 1, shared),
                CategoryScore(SignalCategory.CORPORATE_EVENT, 95.0, 1, shared),
            ],
            WEIGHTS,
        )
        assert result.cleared == (SignalCategory.CORPORATE_EVENT,)


class TestCategoryCombination:
    def test_diminishing_returns(self) -> None:
        """Three actors at 50 compound to 87.5, not 150."""
        assert combine_category(signals("i", 3, 50.0)) == pytest.approx(87.5)

    def test_same_actor_does_not_compound(self) -> None:
        repeated = [
            SubSignal("actor-1", 50.0, "a"),
            SubSignal("actor-1", 50.0, "b"),
            SubSignal("actor-1", 50.0, "c"),
        ]
        assert combine_category(repeated) == pytest.approx(50.0)

    def test_deduplication_keeps_the_strongest(self) -> None:
        kept = deduplicate_by_actor(
            [SubSignal("a", 30.0, "x"), SubSignal("a", 80.0, "y"), SubSignal("b", 10.0, "z")]
        )
        assert {(s.actor_key, s.score) for s in kept} == {("a", 80.0), ("b", 10.0)}

    def test_empty_category_scores_zero(self) -> None:
        assert combine_category([]) == 0.0

    def test_rejects_a_sub_signal_outside_0_100(self) -> None:
        with pytest.raises(ValueError, match="outside 0-100"):
            SubSignal("a", 120.0, "x")


class TestFreshness:
    def test_congressional_decays_from_the_transaction_date(self) -> None:
        """The load-bearing decision in the module.

        A PTR disclosed today covering a 40-day-old trade must not present as
        fresh. Measuring from disclosure would reset the clock.
        """
        value = freshness(
            "congressional_ptr",
            as_of=date(2026, 6, 1),
            transaction_date=date(2026, 4, 22),  # 40 days earlier
            disclosure_date=date(2026, 6, 1),  # disclosed today
            weights=WEIGHTS,
        )
        assert value < 10, f"A 40-day-old PTR scored {value:.1f} freshness"

    def test_a_fresh_form4_beats_a_stale_ptr_at_equal_value(self) -> None:
        """Phase 4 criterion 6, verified here since the maths is shared."""
        ptr = freshness(
            "congressional_ptr",
            as_of=date(2026, 6, 1),
            transaction_date=date(2026, 4, 17),
            disclosure_date=date(2026, 6, 1),
            weights=WEIGHTS,
        )
        form4 = freshness(
            "form4_purchase",
            as_of=date(2026, 6, 1),
            transaction_date=date(2026, 5, 30),
            disclosure_date=date(2026, 6, 1),
            weights=WEIGHTS,
        )
        assert form4 > ptr

    def test_half_life_behaves_as_a_half_life(self) -> None:
        value = freshness(
            "form4_purchase",
            as_of=date(2026, 6, 1),
            transaction_date=date(2026, 5, 11),  # 21 days = one half-life
            disclosure_date=date(2026, 5, 11),
            weights=WEIGHTS,
        )
        assert value == pytest.approx(50.0, abs=0.5)

    def test_13f_decays_slowly_because_it_arrives_stale(self) -> None:
        thirteen_f = WEIGHTS.half_life("thirteen_f")
        assert thirteen_f > WEIGHTS.half_life("form4_purchase") * 4


class TestNormalization:
    def test_threshold_interpolation_is_clamped(self) -> None:
        """A $500M purchase scores 100, not 400.

        Extrapolating past the curve would let one outlier dominate the system.
        """
        curve = [(0.0, 0.0), (1_000_000.0, 80.0), (10_000_000.0, 100.0)]
        assert interpolate(curve, -5) == 0.0
        assert interpolate(curve, 500_000_000) == 100.0
        assert interpolate(curve, 500_000.0) == pytest.approx(40.0)

    def test_missing_input_returns_none_not_zero(self) -> None:
        """ "No purchases" and "purchases worth nothing" are different."""
        assert normalize("insider_purchase_value_usd", None, WEIGHTS) is None

    def test_falls_back_to_threshold_below_the_observation_floor(self) -> None:
        result = normalize("insider_purchase_value_usd", 250_000, WEIGHTS, distribution=[1.0] * 10)
        assert result is not None
        assert result.method is NormalizationMethod.FALLBACK_THRESHOLD

    def test_uses_percentile_when_the_sample_is_large_enough(self) -> None:
        distribution = [float(i) for i in range(WEIGHTS.min_observations + 1)]
        result = normalize("insider_purchase_value_usd", 250.0, WEIGHTS, distribution=distribution)
        assert result is not None
        assert result.method is NormalizationMethod.PERCENTILE

    def test_unknown_feature_raises_rather_than_defaulting(self) -> None:
        with pytest.raises(KeyError, match="No threshold curve"):
            normalize("invented_feature", 1.0, WEIGHTS)

    def test_percentile_rank(self) -> None:
        assert percentile_rank([1.0, 2.0, 3.0, 4.0], 3.0) == pytest.approx(50.0)


class TestScoreProvenance:
    """Phase 3 criterion 5."""

    def _row(self):
        return score_company(
            "0000000009",
            AS_OF,
            WEIGHTS,
            FactSet(
                cik="0000000009",
                as_of=AS_OF,
                category_signals={SignalCategory.CORPORATE_INSIDER: signals("i", 2, 70.0)},
                available_data=ALL_DATA,
            ),
        )

    def test_every_row_carries_version_and_method(self) -> None:
        row = self._row()
        assert row.weights_version == WEIGHTS.version
        assert row.normalization is NormalizationMethod.FALLBACK_THRESHOLD

    def test_weights_hash_is_recorded(self) -> None:
        """So a file edited without bumping its version is detectable later."""
        assert self._row().weights_hash == WEIGHTS.file_hash

    def test_v1_confidence_cannot_exceed_the_cap(self) -> None:
        """SPEC §6.7. Every V1 score is threshold-normalized, so ×0.7 applies."""
        best = compute_composites(
            [CategoryScore(c, 100.0, 5) for c in SignalCategory],
            convergence=100.0,
            contradiction=0.0,
            data_quality=100.0,
            category_coverage=1.0,
            normalization=NormalizationMethod.FALLBACK_THRESHOLD,
            weights=WEIGHTS,
        )
        assert best.confidence <= V1_CONFIDENCE_CAP
