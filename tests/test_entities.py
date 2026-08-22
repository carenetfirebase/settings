"""Entity resolution — SPEC §5, the crux.

The asymmetry these tests protect: a false negative loses one signal, a false
positive manufactures convergence that does not exist.
"""

from __future__ import annotations

from datetime import date
from typing import ClassVar

import pytest

from imt.entities import (
    CONFIDENCE_THRESHOLD,
    Candidate,
    EntityResolver,
    InvalidCIKError,
    MatchMethod,
    TickerMap,
    normalize_cik,
    normalize_name,
    normalize_ticker,
)


class TestNormalizeName:
    def test_phase1_criterion_5(self) -> None:
        """The exact acceptance criterion from docs/PHASES.md Phase 1 #5."""
        assert normalize_name("THE ACME HOLDINGS CORP.") == "ACME"

    @pytest.mark.parametrize(
        ("raw", "expected"),
        [
            ("Apple Inc.", "APPLE"),
            ("The Coca-Cola Company", "COCA COLA"),
            ("Berkshire Hathaway Inc", "BERKSHIRE HATHAWAY"),
            ("JPMorgan Chase & Co.", "JPMORGAN CHASE"),
            ("Alphabet Inc", "ALPHABET"),
            ("  Extra   Spaces  Corp  ", "EXTRA SPACES"),
            ("", ""),
        ],
    )
    def test_common_shapes(self, raw: str, expected: str) -> None:
        assert normalize_name(raw) == expected

    def test_suffix_stripping_is_anchored_to_the_end(self) -> None:
        """Unanchored stripping is a real defect, not a hypothetical one.

        'GROUP' is a legitimate suffix, but it is also the first word of a real
        listed company. Stripping it wherever it appears silently rewrites the
        name and the join fails.
        """
        assert normalize_name("Group 1 Automotive, Inc.") == "GROUP 1 AUTOMOTIVE"

    def test_leading_article_only_stripped_at_the_front(self) -> None:
        """'THE' is an article at the front and a word anywhere else."""
        assert normalize_name("The Acme Corp") == "ACME"
        # Interior article survives: stripping it would merge two distinct names.
        assert normalize_name("Smith And The Jones Corp") == "SMITH AND THE JONES"
        assert normalize_name("Bath & Body Works") == "BATH BODY WORKS"

    def test_repeated_suffixes_are_all_removed(self) -> None:
        assert normalize_name("ACME HOLDINGS CORP") == "ACME"
        assert normalize_name("ACME GROUP HOLDINGS INC") == "ACME"

    def test_never_strips_a_name_to_nothing(self) -> None:
        """A company genuinely called "Group" must not normalize to ''."""
        assert normalize_name("Group") == "GROUP"
        assert normalize_name("The Co") == "CO"


class TestIdentifiers:
    @pytest.mark.parametrize(
        ("raw", "expected"),
        [
            (320193, "0000320193"),
            ("320193", "0000320193"),
            ("0000320193", "0000320193"),
            ("CIK0000320193", "0000320193"),
        ],
    )
    def test_normalize_cik(self, raw: str | int, expected: str) -> None:
        assert normalize_cik(raw) == expected

    def test_rejects_nonsense(self) -> None:
        with pytest.raises(InvalidCIKError):
            normalize_cik("not-a-cik")

    def test_normalize_ticker_preserves_class_suffix(self) -> None:
        assert normalize_ticker(" brk.b ") == "BRK.B"


class TestTickerMap:
    """Tickers are reused across companies. A lookup without a date is a bug."""

    def _map(self) -> TickerMap:
        return TickerMap(
            [
                ("XYZ", "0000000001", date(2015, 1, 1), date(2019, 6, 30)),
                ("XYZ", "0000000002", date(2021, 1, 1), None),
            ]
        )

    def test_resolves_to_the_company_holding_it_at_that_time(self) -> None:
        mapping = self._map()
        assert mapping.resolve("XYZ", date(2018, 5, 1)) == "0000000001"
        assert mapping.resolve("XYZ", date(2023, 5, 1)) == "0000000002"

    def test_gap_between_holders_resolves_to_nothing(self) -> None:
        """Between delisting and reissue the ticker belonged to nobody.

        Returning the later company here would attribute a 2020 filing to a
        company that did not yet have the ticker.
        """
        assert self._map().resolve("XYZ", date(2020, 5, 1)) is None


class TestResolver:
    CANDIDATES: ClassVar[list[Candidate]] = [
        Candidate(cik="0000320193", name="Apple Inc."),
        Candidate(cik="0000789019", name="Microsoft Corporation"),
        Candidate(cik="0001018724", name="Amazon.com, Inc."),
    ]

    def test_manual_override_always_wins(self) -> None:
        resolver = EntityResolver(
            self.CANDIDATES, overrides={("usaspending", "WEIRD NAME LLC"): "0000320193"}
        )
        match = resolver.resolve("usaspending", "WEIRD NAME LLC", as_of=date(2026, 1, 1))
        assert match.resolved_cik == "0000320193"
        assert match.method == MatchMethod.MANUAL_OVERRIDE
        assert match.passes_gate

    def test_ticker_in_ptr_prose_is_extracted(self) -> None:
        """Congressional PTRs embed the ticker in an asset description."""
        ticker_map = TickerMap([("AAPL", "0000320193", date(2000, 1, 1), None)])
        resolver = EntityResolver(self.CANDIDATES, ticker_map=ticker_map, overrides={})
        match = resolver.resolve(
            "house_ptr",
            "row-1",
            as_of=date(2026, 1, 1),
            free_text="Apple Inc. (AAPL) Common Stock",
        )
        assert match.resolved_cik == "0000320193"
        assert match.method == MatchMethod.TICKER_EXACT
        assert match.passes_gate

    def test_exact_normalized_name_resolves(self) -> None:
        resolver = EntityResolver(self.CANDIDATES, overrides={})
        match = resolver.resolve(
            "usaspending", "APPLE INC", as_of=date(2026, 1, 1), free_text="Apple, Inc."
        )
        assert match.resolved_cik == "0000320193"
        assert match.method == MatchMethod.NAME_EXACT

    def test_ambiguous_exact_name_refuses_to_guess(self) -> None:
        """Two listed companies normalizing to the same name is not a match."""
        resolver = EntityResolver(
            [Candidate("0000000001", "Acme Corp"), Candidate("0000000002", "Acme Inc")],
            overrides={},
        )
        match = resolver.resolve("usaspending", "Acme", as_of=date(2026, 1, 1))
        assert match.resolved_cik is None
        assert not match.passes_gate
        assert len(match.runners_up) == 2

    def test_unrelated_name_does_not_resolve(self) -> None:
        resolver = EntityResolver(self.CANDIDATES, overrides={})
        match = resolver.resolve(
            "usaspending",
            "Zeta Manufacturing Services",
            as_of=date(2026, 1, 1),
        )
        assert match.resolved_cik is None
        assert match.confidence < CONFIDENCE_THRESHOLD

    def test_below_gate_never_returns_a_cik(self) -> None:
        """The hard gate from SPEC §5.2.

        A sub-threshold match must not carry a CIK at all -- if it did, a
        caller could read ``resolved_cik`` without checking ``confidence`` and
        feed a wrong join into scoring.
        """
        resolver = EntityResolver(self.CANDIDATES, overrides={})
        for key in ("Micro Corp", "Amazon Web", "Appl"):
            match = resolver.resolve("usaspending", key, as_of=date(2026, 1, 1))
            if match.confidence < CONFIDENCE_THRESHOLD:
                assert match.resolved_cik is None, f"{key} leaked a CIK below the gate"
