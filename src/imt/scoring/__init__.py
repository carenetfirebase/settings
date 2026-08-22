"""Scoring: normalization, category scores, convergence, contradiction.

Nothing in this package may call ``datetime.now()``, ``date.today()`` or
``time.time()`` — the as-of date is always an argument (SPEC §7.5). An
AST-level test enforces it.
"""

from imt.scoring.weights import (
    MAX_SINGLE_CATEGORY_WEIGHT,
    NORMALIZED_SUM_TOLERANCE,
    Weights,
    WeightsValidationError,
    load_weights,
)

__all__ = [
    "MAX_SINGLE_CATEGORY_WEIGHT",
    "NORMALIZED_SUM_TOLERANCE",
    "Weights",
    "WeightsValidationError",
    "load_weights",
]
