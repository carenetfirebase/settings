"""Resolving a source's own identifier to a CIK, with a confidence.

This is the crux of the system (SPEC §5). Convergence across categories is only
meaningful if the categories are talking about the same company, and the cost
of the two error directions is wildly asymmetric:

* a **false negative** loses one signal;
* a **false positive** *manufactures convergence that does not exist*, which
  makes the product actively misleading rather than merely incomplete.

So the gate is deliberately harsh. Anything below ``CONFIDENCE_THRESHOLD``
(0.85) never reaches scoring; it goes to the review queue where a human can
look at it. Nothing is force-matched to its best candidate, and nothing is
silently dropped.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from datetime import date
from enum import StrEnum
from pathlib import Path

from rapidfuzz import fuzz

from imt.core.config import config_dir
from imt.entities.identifiers import looks_like_ticker, normalize_cik, normalize_ticker
from imt.entities.normalize import normalize_name

CONFIDENCE_THRESHOLD = 0.85


class MatchMethod(StrEnum):
    MANUAL_OVERRIDE = "manual_override"
    CIK_DIRECT = "cik_direct"
    TICKER_EXACT = "ticker_exact"
    NAME_EXACT = "name_exact"
    NAME_FUZZY = "name_fuzzy"
    UNRESOLVED = "unresolved"


@dataclass(frozen=True, slots=True)
class Candidate:
    cik: str
    name: str


@dataclass(frozen=True, slots=True)
class EntityMatch:
    source: str
    source_key: str
    resolved_cik: str | None
    method: MatchMethod
    confidence: float
    # Populated when the match failed the gate, so the review queue can show a
    # human what the alternatives were rather than just "unresolved".
    runners_up: tuple[tuple[str, float], ...] = ()

    @property
    def passes_gate(self) -> bool:
        return self.resolved_cik is not None and self.confidence >= CONFIDENCE_THRESHOLD


# Method-specific ceilings. A fuzzy name match can never be as trustworthy as a
# ticker hit against the point-in-time map, and encoding that here stops a
# high similarity score from impersonating certainty.
_METHOD_CONFIDENCE = {
    MatchMethod.MANUAL_OVERRIDE: 1.00,
    MatchMethod.CIK_DIRECT: 1.00,
    MatchMethod.TICKER_EXACT: 0.98,
    MatchMethod.NAME_EXACT: 0.92,
}

_TICKER_IN_TEXT = re.compile(r"\(([A-Z]{1,5}(?:[.-][A-Z]{1,4})?)\)")


def load_overrides(path: Path | None = None) -> dict[tuple[str, str], str]:
    """``config/overrides/entity_map.csv``. Always wins (SPEC §5.3)."""
    target = path or config_dir() / "overrides" / "entity_map.csv"
    overrides: dict[tuple[str, str], str] = {}
    if not target.is_file():
        return overrides
    with target.open("r", encoding="utf-8", newline="") as fh:
        rows = (line for line in fh if not line.lstrip().startswith("#"))
        for row in csv.DictReader(rows):
            if not row.get("source") or not row.get("source_key") or not row.get("cik"):
                continue
            overrides[(row["source"].strip(), row["source_key"].strip())] = normalize_cik(
                row["cik"]
            )
    return overrides


class TickerMap:
    """Point-in-time ticker → CIK resolution.

    Tickers are reused by different companies over time, so a lookup without a
    date is a bug waiting to happen. This class refuses to do one.
    """

    def __init__(self, rows: list[tuple[str, str, date, date | None]]) -> None:
        # (ticker, cik, valid_from, valid_to)
        self._rows = rows

    def resolve(self, ticker: str, as_of: date) -> str | None:
        want = normalize_ticker(ticker)
        for tic, cik, valid_from, valid_to in self._rows:
            if tic != want:
                continue
            if valid_from <= as_of and (valid_to is None or as_of <= valid_to):
                return cik
        return None


class EntityResolver:
    def __init__(
        self,
        candidates: list[Candidate],
        *,
        ticker_map: TickerMap | None = None,
        overrides: dict[tuple[str, str], str] | None = None,
    ) -> None:
        self._candidates = candidates
        self._ticker_map = ticker_map
        self._overrides = overrides if overrides is not None else load_overrides()
        self._by_normalized: dict[str, list[Candidate]] = {}
        for candidate in candidates:
            self._by_normalized.setdefault(normalize_name(candidate.name), []).append(candidate)

    def resolve(
        self,
        source: str,
        source_key: str,
        *,
        as_of: date,
        free_text: str | None = None,
    ) -> EntityMatch:
        """Resolve one source key, trying strategies strongest-first."""
        override = self._overrides.get((source, source_key))
        if override is not None:
            return EntityMatch(
                source,
                source_key,
                override,
                MatchMethod.MANUAL_OVERRIDE,
                _METHOD_CONFIDENCE[MatchMethod.MANUAL_OVERRIDE],
            )

        text = free_text if free_text is not None else source_key

        ticker_match = self._try_ticker(source, source_key, text, as_of)
        if ticker_match is not None:
            return ticker_match

        normalized = normalize_name(text)
        exact = self._by_normalized.get(normalized)
        if exact and len(exact) == 1:
            return EntityMatch(
                source,
                source_key,
                exact[0].cik,
                MatchMethod.NAME_EXACT,
                _METHOD_CONFIDENCE[MatchMethod.NAME_EXACT],
            )
        if exact and len(exact) > 1:
            # Two listed companies normalize to the same name. Never guess.
            return EntityMatch(
                source,
                source_key,
                None,
                MatchMethod.UNRESOLVED,
                0.0,
                runners_up=tuple((c.cik, 1.0) for c in exact[:5]),
            )

        return self._try_fuzzy(source, source_key, normalized)

    def _try_ticker(
        self, source: str, source_key: str, text: str, as_of: date
    ) -> EntityMatch | None:
        if self._ticker_map is None:
            return None
        candidates: list[str] = []
        # Parenthesised tickers first: PTR asset descriptions look like
        # "Apple Inc. (AAPL) Common Stock".
        candidates.extend(_TICKER_IN_TEXT.findall(text.upper()))
        stripped = text.strip().upper()
        if looks_like_ticker(stripped):
            candidates.append(stripped)
        for candidate in candidates:
            cik = self._ticker_map.resolve(candidate, as_of)
            if cik is not None:
                return EntityMatch(
                    source,
                    source_key,
                    cik,
                    MatchMethod.TICKER_EXACT,
                    _METHOD_CONFIDENCE[MatchMethod.TICKER_EXACT],
                )
        return None

    def _try_fuzzy(self, source: str, source_key: str, normalized: str) -> EntityMatch:
        if not normalized or not self._candidates:
            return EntityMatch(source, source_key, None, MatchMethod.UNRESOLVED, 0.0)

        scored: list[tuple[Candidate, float]] = []
        for candidate in self._candidates:
            score = fuzz.token_set_ratio(normalized, normalize_name(candidate.name)) / 100.0
            if score > 0.6:
                scored.append((candidate, score))
        if not scored:
            return EntityMatch(source, source_key, None, MatchMethod.UNRESOLVED, 0.0)

        scored.sort(key=lambda pair: (-pair[1], pair[0].cik))
        best, best_score = scored[0]

        # A fuzzy match is only as good as its margin. If the runner-up is
        # nearly as good, the "best" candidate is not evidence of anything --
        # this is the case that silently manufactures convergence.
        margin = best_score - scored[1][1] if len(scored) > 1 else best_score
        confidence = round(min(best_score, 0.60 + margin) * best_score, 4)

        return EntityMatch(
            source,
            source_key,
            best.cik if confidence >= CONFIDENCE_THRESHOLD else None,
            MatchMethod.NAME_FUZZY
            if confidence >= CONFIDENCE_THRESHOLD
            else MatchMethod.UNRESOLVED,
            confidence,
            runners_up=tuple((c.cik, round(s, 4)) for c, s in scored[:5]),
        )
