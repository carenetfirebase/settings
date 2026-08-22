"""CIK and ticker canonicalization.

CIK is the identity key for the whole system (SPEC §5). Tickers are attributes
with a validity range and are never used to join across time — see
``imt.entities.resolver.resolve_ticker_as_of``.
"""

from __future__ import annotations

import re

_TICKER_OK = re.compile(r"^[A-Z0-9]{1,5}([.-][A-Z]{1,4})?$")


class InvalidCIKError(ValueError):
    pass


def normalize_cik(raw: str | int) -> str:
    """Zero-pad to the 10-digit form used in URLs, keys, and the API surface.

    >>> normalize_cik(320193)
    '0000320193'
    >>> normalize_cik("CIK0000320193")
    '0000320193'
    """
    if isinstance(raw, int):
        digits = str(raw)
    else:
        text = raw.strip().upper()
        text = text.removeprefix("CIK")
        digits = text.lstrip("0") or "0"
        if not text.isdigit():
            digits = "".join(ch for ch in text if ch.isdigit())
    if not digits or not digits.isdigit():
        raise InvalidCIKError(f"Not a CIK: {raw!r}")
    if len(digits) > 10:
        raise InvalidCIKError(f"CIK too long: {raw!r}")
    return digits.zfill(10)


def normalize_ticker(raw: str) -> str:
    """Uppercase and trim. Does not validate that the ticker exists.

    Class shares arrive as ``BRK.B`` or ``BRK-B`` depending on the source; both
    are preserved as given after case folding, because the point-in-time ticker
    map stores whatever the source used and resolution happens against that.
    """
    return raw.strip().upper()


def looks_like_ticker(raw: str) -> bool:
    """Cheap gate before hitting the ticker map with free text.

    Congressional PTRs embed tickers in prose ("Apple Inc. (AAPL) Common
    Stock"), so extraction produces plenty of candidates that are really words.
    """
    return bool(_TICKER_OK.match(raw.strip().upper()))
