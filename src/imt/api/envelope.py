"""The universal response envelope. docs/API_CONTRACT.md.

``meta`` is not decoration. The UI's stale and failed states are driven
entirely by it, so a route that returns bare data has silently disabled two of
the four panel states that UI_SPEC §4.10 requires.

A test asserts every scored route returns ``weights_version`` and
``normalization``.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

SourceStatus = Literal["current", "delayed", "stale", "unavailable", "failed"]


class SourceState(BaseModel):
    id: str
    status: SourceStatus
    last_success: datetime | None = None
    reason: str | None = None


class Coverage(BaseModel):
    categories_available: int
    categories_total: int


class Meta(BaseModel):
    as_of: date | None = None
    generated_at: datetime
    data_quality: int | None = None
    sources: list[SourceState] = Field(default_factory=list)
    # Present on any scored response. Absence is a bug, not a default.
    weights_version: str | None = None
    normalization: str | None = None
    coverage: Coverage | None = None
    next_cursor: str | None = None


class Envelope[T](BaseModel):
    data: T
    meta: Meta


class ErrorBody(BaseModel):
    code: str
    message: str
    retry_at: datetime | None = None
    affected_panels: list[str] = Field(default_factory=list)


class ErrorEnvelope(BaseModel):
    error: ErrorBody
