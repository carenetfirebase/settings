"""Weights loading and validation.

The two rules here fail *silently* if violated — the system keeps producing
numbers, they are just meaningless. That is why they are load-time errors.
"""

from __future__ import annotations

import math
from pathlib import Path

import pytest
import yaml

from imt.scoring import MAX_SINGLE_CATEGORY_WEIGHT, WeightsValidationError, load_weights


@pytest.fixture
def raw_weights() -> dict:
    return yaml.safe_load((Path("config/weights.yaml")).read_text(encoding="utf-8"))


def _write(tmp_path: Path, payload: dict) -> Path:
    target = tmp_path / "weights.yaml"
    target.write_text(yaml.safe_dump(payload), encoding="utf-8")
    return target


def convergence(n_categories: int, weight: float, lambda_: float) -> float:
    """SPEC §6.4, at full category strength."""
    return 100.0 * (1.0 - math.exp(-lambda_ * n_categories * weight))


class TestShippedWeightsAreCalibrated:
    def test_spec_6_4_calibration_holds(self) -> None:
        """Three strong categories ~= 75 and five ~= 92 (SPEC §6.4)."""
        weights = load_weights()
        average = sum(weights.category_weights.values()) / len(weights.category_weights)
        assert convergence(3, average, weights.lambda_) == pytest.approx(75, abs=5)
        assert convergence(5, average, weights.lambda_) == pytest.approx(92, abs=5)

    def test_one_category_cannot_look_like_convergence(self) -> None:
        """The premise of the entire product, checked against the shipped file."""
        weights = load_weights()
        for name, weight in weights.category_weights.items():
            reached = convergence(1, weight, weights.lambda_)
            assert reached < 45, f"{name} alone reaches Convergence {reached:.1f}"

    def test_version_and_hash_are_recorded(self) -> None:
        weights = load_weights()
        assert weights.version == "0.1.0"
        assert len(weights.file_hash) == 64


class TestValidation:
    def test_rejects_weights_normalized_to_one(self, raw_weights: dict, tmp_path: Path) -> None:
        """docs/PHASES.md Phase 3 #10 — the normalization trap.

        Normalizing these to sum to 1.0 is the natural thing to do to anything
        called "weights", and it takes three strong categories from 75 to 15
        without raising anything.
        """
        n = len(raw_weights["category_weights"])
        raw_weights["category_weights"] = {k: 1.0 / n for k in raw_weights["category_weights"]}
        with pytest.raises(WeightsValidationError, match="looks normalized"):
            load_weights(_write(tmp_path, raw_weights))

    def test_rejects_a_single_category_weighted_too_heavily(
        self, raw_weights: dict, tmp_path: Path
    ) -> None:
        """Weighting the flagship category up is the obvious thing to want."""
        raw_weights["category_weights"]["corporate_insider"] = 1.2
        with pytest.raises(WeightsValidationError, match="exceeds the maximum"):
            load_weights(_write(tmp_path, raw_weights))

    def test_the_bound_is_where_the_arithmetic_says_it_is(self) -> None:
        """1.05 is not arbitrary: Convergence crosses 45 at w = 1.087."""
        assert convergence(1, MAX_SINGLE_CATEGORY_WEIGHT, 0.55) < 45
        assert convergence(1, 1.09, 0.55) > 45

    def test_rejects_a_missing_category(self, raw_weights: dict, tmp_path: Path) -> None:
        del raw_weights["category_weights"]["political"]
        with pytest.raises(WeightsValidationError, match="missing"):
            load_weights(_write(tmp_path, raw_weights))

    def test_rejects_base_weights_that_do_not_sum_to_one(
        self, raw_weights: dict, tmp_path: Path
    ) -> None:
        """base_weights ARE a weighted mean, so here summing to 1 is required."""
        raw_weights["base_weights"]["informed_money"] = 0.9
        with pytest.raises(WeightsValidationError, match="base_weights must sum"):
            load_weights(_write(tmp_path, raw_weights))

    def test_rejects_a_non_semver_version(self, raw_weights: dict, tmp_path: Path) -> None:
        raw_weights["weights_version"] = "v1"
        with pytest.raises(WeightsValidationError, match="semver"):
            load_weights(_write(tmp_path, raw_weights))


def test_missing_half_life_raises_rather_than_defaulting() -> None:
    """SPEC §6.5: decay is per-source. A shared default is the bug it warns about."""
    weights = load_weights()
    assert weights.half_life("congressional_ptr") == 10
    assert weights.half_life("thirteen_f") == 120
    with pytest.raises(KeyError, match="no default"):
        weights.half_life("invented_event_type")


def test_congressional_decays_faster_than_form4() -> None:
    """SPEC §6.5 calls the PTR half-life 'aggressive' — verify it actually is."""
    weights = load_weights()
    assert weights.half_life("congressional_ptr") < weights.half_life("form4_purchase")
