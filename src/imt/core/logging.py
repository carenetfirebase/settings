"""Structured logging. JSON to file, human-readable to console.

Never log a secret and never log a full raw payload — payloads go to
``raw_documents``, where they are addressable, not into a log file where they
are merely large.
"""

from __future__ import annotations

import logging
import sys
from typing import Any

import structlog

_SECRET_KEYS = frozenset(
    {
        "api_key",
        "apikey",
        "token",
        "password",
        "secret",
        "authorization",
        "fred_api_key",
        "eia_api_key",
        "sam_api_key",
        "finra_api_key",
        "openfda_api_key",
    }
)

_MAX_VALUE_CHARS = 512


def _redact(
    _logger: Any, _method: str, event_dict: structlog.types.EventDict
) -> structlog.types.EventDict:
    """Redact anything that looks like a credential; truncate anything huge."""
    for key in list(event_dict):
        lowered = key.lower()
        if any(marker in lowered for marker in _SECRET_KEYS):
            event_dict[key] = "***redacted***"
            continue
        value = event_dict[key]
        if isinstance(value, str | bytes) and len(value) > _MAX_VALUE_CHARS:
            event_dict[key] = f"<{type(value).__name__} len={len(value)} truncated>"
    return event_dict


def configure_logging(level: str = "INFO", *, json_output: bool = False) -> None:
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level.upper())
    renderer: Any = (
        structlog.processors.JSONRenderer()
        if json_output
        else structlog.dev.ConsoleRenderer(colors=False)
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            _redact,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelNamesMapping()[level.upper()]
        ),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    logger: structlog.stdlib.BoundLogger = structlog.get_logger(name)
    return logger
