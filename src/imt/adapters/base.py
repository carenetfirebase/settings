"""Provider protocols.

Every external source sits behind one of these. Swapping a free provider for a
paid one later must touch only ``adapters/`` and ``config/sources.yaml`` — no
feature, scorer, or route may name a provider.

Adapters do two things and no more: fetch bytes through ``core.http`` and turn
them into typed records. They do not open database sessions, resolve entities,
or compute features. Keeping parsing pure is what lets the whole Form 4 corpus
be re-parsed from ``raw_documents`` when a parser bug is found, without
re-fetching from an API that rate-limits at 10 requests a second.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from datetime import date
from typing import Protocol, runtime_checkable

from imt.adapters.records import (
    ActivistRecord,
    ContractRecord,
    FilingRef,
    FundamentalFact,
    InsiderTransactionRecord,
    MacroPoint,
    PoliticalTradeRecord,
    PriceBar,
)


@runtime_checkable
class MarketDataProvider(Protocol):
    """EOD price series. V1: Stooq. Second adapter yfinance, disabled."""

    source_id: str

    def daily_bars(self, symbol: str, *, start: date, end: date) -> Sequence[PriceBar]: ...


@runtime_checkable
class FilingsProvider(Protocol):
    """SEC EDGAR discovery and document retrieval."""

    source_id: str

    def daily_index(self, day: date) -> Sequence[FilingRef]: ...

    def submissions(self, cik: str) -> Sequence[FilingRef]: ...

    def document(self, ref: FilingRef) -> bytes: ...


@runtime_checkable
class InsiderDataProvider(Protocol):
    source_id: str

    def parse_form4(
        self, payload: bytes, *, ref: FilingRef
    ) -> Sequence[InsiderTransactionRecord]: ...


@runtime_checkable
class ActivistDataProvider(Protocol):
    source_id: str

    def parse_ownership(self, payload: bytes, *, ref: FilingRef) -> Sequence[ActivistRecord]: ...


@runtime_checkable
class PoliticalDataProvider(Protocol):
    """House PTR and Senate eFD.

    Senate is manual-import only in V1 (DATA_SOURCES Tier 3), so its
    implementation reads a CSV rather than making a request. Both satisfy this
    protocol, which is the point — the ingest job does not care which.
    """

    source_id: str

    def transactions(self, *, year: int) -> Iterable[PoliticalTradeRecord]: ...


@runtime_checkable
class FundamentalsProvider(Protocol):
    source_id: str

    def company_facts(self, cik: str) -> Sequence[FundamentalFact]: ...


@runtime_checkable
class ContractsProvider(Protocol):
    source_id: str

    def awards(self, *, start: date, end: date) -> Iterable[ContractRecord]: ...


@runtime_checkable
class MacroProvider(Protocol):
    source_id: str

    def series(self, series_id: str, *, start: date) -> Sequence[MacroPoint]: ...


@runtime_checkable
class OptionsDataProvider(Protocol):
    """OCC EOD public options positioning.

    Per-symbol open interest at scale is Premium-Dependent (DATA_SOURCES
    Tier 2). This protocol exists so the interface is built and the feature is
    disabled, rather than approximated.
    """

    source_id: str

    def positioning(self, *, day: date) -> Iterable[object]: ...
