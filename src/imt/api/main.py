"""FastAPI application. Bound to loopback, no auth, single-user local app.

The API is **read-only**: it holds a database role with no write grants and
every route is a GET. Ingestion and scoring happen in CLI jobs. That separation
is what makes refreshing the dashboard incapable of corrupting a backtest.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from imt.api.routers import congress, feed, health, signals, system
from imt.core.config import get_settings
from imt.core.logging import configure_logging

API_PREFIX = "/api/v1"


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(
        title="Informed Money Terminal",
        version="0.1.0",
        description=(
            "Local research terminal. Ranks public-evidence convergence. "
            "Not a source of buy/sell recommendations."
        ),
        docs_url="/docs",
        openapi_url="/openapi.json",
    )

    # The Next.js dev server proxies to this origin. Loopback only -- there is
    # no scenario where this API should answer a request from another machine.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
        allow_methods=["GET"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    # Also under /api so the Next.js proxy reaches it: the dev server
    # rewrites /api/* to this origin, and Phase 1 criterion 3 curls
    # /api/health through that proxy.
    app.include_router(health.router, prefix="/api")
    app.include_router(system.router, prefix=API_PREFIX)
    app.include_router(feed.router, prefix=API_PREFIX)
    app.include_router(signals.router, prefix=API_PREFIX)
    app.include_router(congress.router, prefix=API_PREFIX)
    return app


app = create_app()


@app.get("/health", tags=["system"])
def health_root() -> dict[str, Any]:
    """Unprefixed alias. Phase 1 criterion 2 curls this exact path."""
    return health.health_payload()
