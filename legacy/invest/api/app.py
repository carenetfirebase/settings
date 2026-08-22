"""Read-only local API over the research database.

**Local, read-only, unauthenticated — and those three go together.** There is
no auth because it is meant to bind to 127.0.0.1 and serve one person on one
machine. That is only safe because it is also read-only at the database level
and never binds to a public interface by default. If you expose this, you are
publishing your research database to whoever can reach the port.

Design notes:

* Every route is a GET. A test enumerates the route table and fails if
  anything else appears, so "read-only" cannot quietly stop being true.
* Every data route accepts `as_of`, so point-in-time is the default posture
  rather than something a caller has to remember to request.
* Political disclosures are served, clearly labelled `investigate_only` on the
  wire. Serving them for a human to read is the point; they still cannot reach
  a score, which is enforced in the scoring engine, not here.
"""

from __future__ import annotations

import pathlib
from datetime import UTC, date, datetime

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from invest import __version__
from invest.api.deps import as_of_param, get_readonly_session, resolve_ticker
from invest.api.schemas import (
    AnalysisResponse,
    ConflictOut,
    ConflictsResponse,
    DisclosureOut,
    DisclosuresResponse,
    FundamentalOut,
    FundamentalsResponse,
    HealthResponse,
    InsiderResponse,
    InsiderTransactionOut,
    Meta,
    PriceBarOut,
    PriceResponse,
    RegimeResponse,
    RegimeSignalOut,
    ScoreOut,
    SecuritySummary,
    SnapshotDetailResponse,
    SnapshotOut,
    SnapshotsResponse,
    UniverseResponse,
)
from invest.db.models import DataConflict, Entity, ResearchSnapshot, Security

DESCRIPTION = """
Read-only local API over an investment research database.

**Nothing here is investment advice, and nothing here is a forecast.**

Conventions:

* A value that could not be computed is `null`, with the reason alongside it
  where one exists. `null` never means zero.
* `value_type` distinguishes `observed` (from a filing or feed), `calculated`
  (deterministic arithmetic), and `estimated` (rests on modelled assumptions).
* Every data endpoint accepts `as_of` for point-in-time queries. A restatement
  filed after that date is invisible, as it was to everyone at the time.
* Congressional disclosures are served for reading and are firewalled from
  every score.
"""


def _meta(as_of: date | None = None, note: str | None = None) -> Meta:
    return Meta(
        as_of=as_of,
        generated_at=datetime.now(UTC),
        note=note,
    )


def _swagger_asset_dir() -> str | None:
    """Locate the bundled Swagger UI assets, if they are installed.

    FastAPI's stock `/docs` loads its CSS and JS from cdn.jsdelivr.net and its
    favicon from fastapi.tiangolo.com. For this project that is a real defect,
    not a cosmetic one: a tool whose premise is local, zero-cost and private
    should not reach out to two third parties in order to render the docs for
    a page that then displays your research. It also breaks entirely on an
    air-gapped or egress-filtered machine — which is exactly where a personal
    research database is most likely to live.

    Serving the assets from the local package fixes all of that.

    Note on versions: FastAPI emits an OpenAPI **3.1** document, and only
    Swagger UI 5.x can parse that — a 4.x bundle renders "Unable to render
    this definition" instead. `swagger-ui-py` ships a current build, so it is
    preferred; the older `swagger-ui-bundle` is accepted only as a fallback.
    """
    try:
        import swagger_ui

        candidate = pathlib.Path(swagger_ui.__file__).parent / "static"
        if (candidate / "swagger-ui-bundle.js").exists():
            return str(candidate)
    except ImportError:  # pragma: no cover
        pass

    try:
        import swagger_ui_bundle
    except ImportError:  # pragma: no cover - only when neither is installed
        return None

    root = pathlib.Path(swagger_ui_bundle.__file__).parent / "vendor"
    for candidate in sorted(root.glob("swagger-ui-*"), reverse=True):
        if (candidate / "swagger-ui-bundle.js").exists():
            return str(candidate)
    return None  # pragma: no cover


def create_app() -> FastAPI:
    swagger_dir = _swagger_asset_dir()

    app = FastAPI(
        title="invest — research API",
        description=DESCRIPTION,
        version=__version__,
        # Replaced below with a self-hosted page when the assets are present.
        docs_url=None if swagger_dir else "/docs",
        redoc_url=None,
    )

    if swagger_dir:
        app.mount(
            "/static/swagger",
            StaticFiles(directory=swagger_dir),
            name="swagger-ui-assets",
        )

        @app.get("/docs", include_in_schema=False, response_class=HTMLResponse)
        def swagger_docs() -> HTMLResponse:
            """Interactive API docs, served entirely from this machine."""
            return get_swagger_ui_html(
                openapi_url="/openapi.json",
                title=f"{app.title} — docs",
                swagger_js_url="/static/swagger/swagger-ui-bundle.js",
                swagger_css_url="/static/swagger/swagger-ui.css",
                # An empty data URI: the stock value fetches a favicon from
                # fastapi.tiangolo.com, which is the last outbound call left.
                swagger_favicon_url="data:,",
            )

    # ---------------------------------------------------------------- health

    @app.get("/health", response_model=HealthResponse, tags=["meta"])
    def health(session: Session = Depends(get_readonly_session)) -> HealthResponse:
        try:
            session.execute(text("SELECT 1"))
            db_status = "ok"
        except Exception as exc:  # pragma: no cover - only on a broken DB
            raise HTTPException(status_code=503, detail=f"database unreachable: {exc}") from exc
        return HealthResponse(status="ok", database=db_status, version=__version__)

    # -------------------------------------------------------------- universe

    @app.get("/universe", response_model=UniverseResponse, tags=["universe"])
    def universe(session: Session = Depends(get_readonly_session)) -> UniverseResponse:
        """The research universe held in the security master."""
        rows = session.execute(
            select(Security, Entity)
            .join(Entity, Security.entity_id == Entity.id)
            .order_by(Security.ticker)
        ).all()

        securities = [
            SecuritySummary(
                ticker=security.ticker,
                name=entity.name,
                cik=entity.cik,
                exchange=security.exchange,
                sector=entity.sector,
                currency=security.currency,
                is_financial=entity.is_financial,
                entity_id=entity.id,
                security_id=security.id,
                data_quality_flag=entity.data_quality_flag,
            )
            for security, entity in rows
        ]
        note = None
        if any(s.data_quality_flag == "unverified_bootstrap" for s in securities):
            note = (
                "Some CIKs have not been verified against SEC EDGAR. "
                "Run `invest universe verify` before trusting fundamentals."
            )
        return UniverseResponse(meta=_meta(note=note), count=len(securities), securities=securities)

    @app.get("/securities/{ticker}", response_model=SecuritySummary, tags=["universe"])
    def security_detail(
        ticker: str, session: Session = Depends(get_readonly_session)
    ) -> SecuritySummary:
        resolved = resolve_ticker(session, ticker)
        entity = session.get(Entity, resolved.entity_id)
        security = session.get(Security, resolved.security_id)
        return SecuritySummary(
            ticker=resolved.ticker,
            name=resolved.name,
            cik=resolved.cik,
            exchange=security.exchange if security else None,
            sector=entity.sector if entity else None,
            currency=resolved.currency,
            is_financial=resolved.is_financial,
            entity_id=resolved.entity_id,
            security_id=resolved.security_id,
            data_quality_flag=entity.data_quality_flag if entity else "ok",
        )

    # ---------------------------------------------------------------- prices

    @app.get("/securities/{ticker}/prices", response_model=PriceResponse, tags=["market data"])
    def prices(
        ticker: str,
        start: date | None = Query(None),
        limit: int = Query(500, ge=1, le=10_000),
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> PriceResponse:
        """Daily OHLCV. Quarantined observations are never returned."""
        from invest.repository import get_price_frame

        resolved = resolve_ticker(session, ticker)
        frame = get_price_frame(session, resolved.security_id, start=start, as_of=as_of)

        bars: list[PriceBarOut] = []
        if not frame.empty:
            for obs_date, row in frame.tail(limit).iterrows():
                bars.append(
                    PriceBarOut(
                        obs_date=obs_date,
                        open=None if row["open"] != row["open"] else float(row["open"]),
                        high=None if row["high"] != row["high"] else float(row["high"]),
                        low=None if row["low"] != row["low"] else float(row["low"]),
                        close=None if row["close"] != row["close"] else float(row["close"]),
                        volume=None if row["volume"] is None else int(row["volume"]),
                        source=row["source"],
                    )
                )

        return PriceResponse(
            meta=_meta(as_of=as_of),
            ticker=resolved.ticker,
            count=len(bars),
            adjustment_note=(
                "Stooq prices are split-adjusted but NOT dividend-adjusted. Do not "
                "compute total returns from these without accounting for dividends."
            ),
            bars=bars,
        )

    # ---------------------------------------------------------- fundamentals

    @app.get(
        "/securities/{ticker}/fundamentals",
        response_model=FundamentalsResponse,
        tags=["fundamentals"],
    )
    def fundamentals(
        ticker: str,
        metric: list[str] | None = Query(None, description="Repeat to request several."),
        years: int = Query(5, ge=1, le=30),
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> FundamentalsResponse:
        """Annual fundamentals, restatement-aware and point-in-time.

        Where a period has been restated, the figure returned is the latest one
        filed on or before `as_of` — what a reader would have seen that day.
        """
        from invest.analysis import REQUIRED_METRICS
        from invest.repository import get_fundamental_series

        resolved = resolve_ticker(session, ticker)
        wanted = metric or list(REQUIRED_METRICS)

        series: dict[str, list[FundamentalOut]] = {}
        available: dict[str, int] = {}
        missing: list[str] = []

        for name in wanted:
            points = get_fundamental_series(
                session, resolved.entity_id, name, as_of=as_of, fiscal_period="FY", limit=years
            )
            if not points:
                missing.append(name)
                continue
            available[name] = len(points)
            series[name] = [
                FundamentalOut(
                    metric_name=p.metric_name,
                    value=p.value,
                    unit=p.unit,
                    period_start=p.period_start,
                    period_end=p.period_end,
                    fiscal_year=p.fiscal_year,
                    fiscal_period=p.fiscal_period,
                    filed_date=p.filed_date,
                    form_type=p.form_type,
                    accession_number=p.accession_number,
                    data_quality_flag=p.data_quality_flag,
                )
                for p in points
            ]

        return FundamentalsResponse(
            meta=_meta(as_of=as_of),
            ticker=resolved.ticker,
            metrics_available=available,
            metrics_missing=missing,
            series=series,
        )

    # -------------------------------------------------------------- analysis

    @app.get("/securities/{ticker}/analysis", response_model=AnalysisResponse, tags=["scores"])
    def analysis(
        ticker: str,
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> AnalysisResponse:
        """Run the full scoring pipeline and return all three scores.

        Does NOT persist a snapshot — this API never writes. Use
        `invest analyze` on the command line when you want an immutable record.
        """
        from invest.analysis import analyze as run_analysis
        from invest.engines.scoring import MODEL_VERSION, PREMIUM_DEPENDENT_INPUTS

        resolved = resolve_ticker(session, ticker)
        result = run_analysis(session, resolved.ticker, as_of=as_of)

        def to_score(score) -> ScoreOut:
            payload = score.as_dict()
            return ScoreOut(**payload)

        meta = _meta(as_of=result.as_of)
        meta.model_version = MODEL_VERSION
        meta.note = (
            "Scores are decomposable: every component and weight is included. "
            "Confidence is permanently capped because premium data is absent."
        )

        return AnalysisResponse(
            meta=meta,
            ticker=resolved.ticker,
            name=resolved.name,
            cik=resolved.cik,
            price=result.inputs_json.get("price"),
            investment_quality=to_score(result.scores.quality),
            trade_setup=to_score(result.scores.setup),
            confidence=to_score(result.scores.confidence),
            components=result.components_json,
            inputs=result.inputs_json,
            warnings=result.scores.all_warnings,
            premium_data_dependent=list(PREMIUM_DEPENDENT_INPUTS),
        )

    @app.get("/securities/{ticker}/report", tags=["scores"])
    def report(
        ticker: str,
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> dict:
        """The rendered research report as plain text."""
        from invest.analysis import analyze as run_analysis

        resolved = resolve_ticker(session, ticker)
        result = run_analysis(session, resolved.ticker, as_of=as_of)
        return {
            "ticker": resolved.ticker,
            "as_of": result.as_of.isoformat(),
            "report_text": result.report_text,
        }

    # ------------------------------------------------------------- snapshots

    @app.get("/snapshots", response_model=SnapshotsResponse, tags=["scores"])
    def snapshots(
        ticker: str | None = Query(None),
        limit: int = Query(50, ge=1, le=500),
        session: Session = Depends(get_readonly_session),
    ) -> SnapshotsResponse:
        """Stored research runs. Immutable by construction."""
        stmt = (
            select(ResearchSnapshot, Security.ticker)
            .join(Security, ResearchSnapshot.security_id == Security.id, isouter=True)
            .order_by(ResearchSnapshot.created_at.desc())
            .limit(limit)
        )
        if ticker:
            stmt = stmt.where(Security.ticker == ticker.upper())

        rows = session.execute(stmt).all()
        snapshots_out = [
            SnapshotOut(
                id=snapshot.id,
                ticker=snapshot_ticker,
                snapshot_date=snapshot.snapshot_date,
                as_of_date=snapshot.as_of_date,
                model_version=snapshot.model_version,
                investment_quality_score=_maybe_float(snapshot.investment_quality_score),
                trade_setup_score=_maybe_float(snapshot.trade_setup_score),
                confidence_score=_maybe_float(snapshot.confidence_score),
                created_at=snapshot.created_at,
            )
            for snapshot, snapshot_ticker in rows
        ]
        return SnapshotsResponse(
            meta=_meta(), count=len(snapshots_out), snapshots=snapshots_out
        )

    @app.get(
        "/snapshots/{snapshot_id}", response_model=SnapshotDetailResponse, tags=["scores"]
    )
    def snapshot_detail(
        snapshot_id: int, session: Session = Depends(get_readonly_session)
    ) -> SnapshotDetailResponse:
        """A stored run in full, including exactly what fed it."""
        snapshot = session.get(ResearchSnapshot, snapshot_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail=f"No snapshot {snapshot_id}")

        security = (
            session.get(Security, snapshot.security_id) if snapshot.security_id else None
        )
        return SnapshotDetailResponse(
            meta=_meta(as_of=snapshot.as_of_date),
            snapshot=SnapshotOut(
                id=snapshot.id,
                ticker=security.ticker if security else None,
                snapshot_date=snapshot.snapshot_date,
                as_of_date=snapshot.as_of_date,
                model_version=snapshot.model_version,
                investment_quality_score=_maybe_float(snapshot.investment_quality_score),
                trade_setup_score=_maybe_float(snapshot.trade_setup_score),
                confidence_score=_maybe_float(snapshot.confidence_score),
                created_at=snapshot.created_at,
            ),
            components=snapshot.components_json,
            inputs=snapshot.inputs_json,
            warnings=snapshot.warnings_json,
            report_text=snapshot.report_text,
        )

    # ------------------------------------------------------------- conflicts

    @app.get("/conflicts", response_model=ConflictsResponse, tags=["data quality"])
    def conflicts(
        ticker: str | None = Query(None),
        severity: str | None = Query(None),
        limit: int = Query(100, ge=1, le=1000),
        session: Session = Depends(get_readonly_session),
    ) -> ConflictsResponse:
        """What the validation gate flagged. Nothing is dropped silently."""
        stmt = select(DataConflict).order_by(DataConflict.detected_at.desc()).limit(limit)
        if ticker:
            security = resolve_ticker(session, ticker)
            stmt = stmt.where(DataConflict.security_id == security.security_id)
        if severity:
            stmt = stmt.where(DataConflict.severity == severity)

        rows = session.scalars(stmt).all()
        return ConflictsResponse(
            meta=_meta(),
            count=len(rows),
            conflicts=[
                ConflictOut(
                    id=c.id,
                    table_name=c.table_name,
                    metric_name=c.metric_name,
                    obs_date=c.obs_date,
                    conflict_type=c.conflict_type,
                    severity=c.severity,
                    source_a=c.source_a,
                    value_a=_maybe_float(c.value_a),
                    source_b=c.source_b,
                    value_b=_maybe_float(c.value_b),
                    detail=c.detail,
                    resolved=c.resolved,
                    detected_at=c.detected_at,
                )
                for c in rows
            ],
        )

    # --------------------------------------------------------------- insider

    @app.get("/securities/{ticker}/insider", response_model=InsiderResponse, tags=["insider"])
    def insider(
        ticker: str,
        lookback: int = Query(180, ge=1, le=1825),
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> InsiderResponse:
        """Form 4 activity, with conviction trades separated from compensation.

        Filtered on `filed_date`: a trade the market did not know about yet is
        not returned.
        """
        from invest.providers.form4 import InsiderSummary, describe_code, is_discretionary
        from invest.repository import get_insider_transactions

        resolved = resolve_ticker(session, ticker)
        cutoff = as_of or date.today()
        records = get_insider_transactions(
            session, resolved.entity_id, as_of=cutoff, lookback_days=lookback
        )
        summary = InsiderSummary(records)

        return InsiderResponse(
            meta=_meta(as_of=cutoff),
            ticker=resolved.ticker,
            total_filings=len(records),
            discretionary_trades=summary.transaction_count,
            buys=len(summary.buys),
            sells=len(summary.sells),
            buy_value=summary.buy_value,
            sell_value=summary.sell_value,
            net_buy_ratio=summary.net_buy_ratio,
            interpretation_note=(
                "Only open-market purchases (P) and sales (S) count as conviction. "
                "Grants, option exercises and tax withholding are reported but carry "
                "no signal weight. Sales are weighted at half a purchase."
            ),
            transactions=[
                InsiderTransactionOut(
                    insider_name=r.insider_name,
                    officer_title=r.officer_title,
                    is_director=r.is_director,
                    is_officer=r.is_officer,
                    transaction_date=r.transaction_date,
                    filed_date=r.filed_date,
                    disclosure_lag_days=(r.filed_date - r.transaction_date).days,
                    transaction_code=r.transaction_code,
                    code_meaning=describe_code(r.transaction_code),
                    is_discretionary=is_discretionary(r.transaction_code),
                    acquired_disposed=r.acquired_disposed,
                    shares=float(r.shares) if r.shares is not None else None,
                    price_per_share=(
                        float(r.price_per_share) if r.price_per_share is not None else None
                    ),
                    is_derivative=r.is_derivative,
                )
                for r in records
            ],
        )

    # ----------------------------------------------------------- disclosures

    @app.get(
        "/securities/{ticker}/disclosures",
        response_model=DisclosuresResponse,
        tags=["firewalled"],
    )
    def disclosures(
        ticker: str,
        lookback: int = Query(365, ge=1, le=3650),
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> DisclosuresResponse:
        """Congressional disclosures — RESEARCH CONTEXT ONLY.

        Firewalled from every score. Served here so a human can read them, with
        the firewall status restated on the wire.
        """
        from invest.ingest.political import get_disclosure_context

        resolved = resolve_ticker(session, ticker)
        cutoff = as_of or date.today()
        context = get_disclosure_context(
            session, resolved.security_id, as_of=cutoff, lookback_days=lookback
        )

        return DisclosuresResponse(
            meta=_meta(as_of=cutoff),
            ticker=resolved.ticker,
            firewall_status="investigate_only",
            firewall_note=(
                "This data contributes NOTHING to any score. Disclosure lags of "
                "30-45 days, bracketed amounts, and ambiguous attribution (spouses, "
                "dependents, blind trusts) make it unsuitable as a signal. Amounts "
                "are the brackets as filed; no midpoint is computed."
            ),
            count=context.count,
            median_disclosure_lag_days=context.median_disclosure_lag_days,
            disclosures=[
                DisclosureOut(
                    politician_name=t.politician_name,
                    chamber=t.chamber,
                    transaction_type=t.transaction_type,
                    transaction_date=t.transaction_date,
                    disclosure_date=t.disclosure_date,
                    disclosure_lag_days=(t.disclosure_date - t.transaction_date).days,
                    amount_range_low=_maybe_float(t.amount_range_low),
                    amount_range_high=_maybe_float(t.amount_range_high),
                    ticker_raw=t.ticker_raw,
                    asset_description=t.asset_description,
                )
                for t in context.trades
            ],
        )

    # ---------------------------------------------------------------- regime

    @app.get("/regime", response_model=RegimeResponse, tags=["macro"])
    def regime(
        as_of: date | None = Depends(as_of_param),
        session: Session = Depends(get_readonly_session),
    ) -> RegimeResponse:
        """Market regime from stored macro data. Not a forecast."""
        from invest.engines.regime import classify_from_database

        cutoff = as_of or date.today()
        assessment = classify_from_database(session, as_of=cutoff)
        payload = assessment.as_dict()

        return RegimeResponse(
            meta=_meta(as_of=cutoff),
            regime=payload["regime"],
            risk_score=payload["risk_score"],
            coverage=payload["coverage"],
            reliable=payload["reliable"],
            signals=[RegimeSignalOut(**s) for s in payload["signals"]],
            note=payload["note"],
        )

    # ------------------------------------------------------------ statistics

    @app.get("/stats", tags=["meta"])
    def stats(session: Session = Depends(get_readonly_session)) -> dict:
        """Row counts — a quick 'what do I actually have?' check."""
        from invest.db.models import Base

        counts: dict[str, int] = {}
        for table in sorted(Base.metadata.tables):
            counts[table] = session.scalar(select(func.count()).select_from(text(table))) or 0
        return {"tables": counts, "generated_at": datetime.now(UTC).isoformat()}

    _allow_head(app)
    return app


class HeadMiddleware(BaseHTTPMiddleware):
    """Answer HEAD wherever we answer GET.

    RFC 9110 §9.1: "All general-purpose servers MUST support the methods GET
    and HEAD." Starlette's own router pairs HEAD with GET automatically, but
    FastAPI's APIRoute does not, so `curl -I` against every endpoint came back
    405 with `allow: GET`.

    Done as middleware rather than by adding HEAD to each route's methods:
    FastAPI generates one OpenAPI operation per method, so widening the routes
    emits a duplicate operation for every path — same operationId, spec noise,
    and a warning apiece. Rewriting the method here keeps the published
    contract exactly what it should be, fourteen GETs and nothing else.

    Note what this does and does not save. The response is still computed in
    full; HEAD spares the client the download, not the server the work.
    """

    async def dispatch(self, request: Request, call_next):
        if request.method != "HEAD":
            return await call_next(request)

        request.scope["method"] = "GET"
        response = await call_next(request)

        body = b"".join([chunk async for chunk in response.body_iterator])
        headers = dict(response.headers)
        # Report the length the equivalent GET would return — that is the
        # entire point of asking — while sending no body.
        headers["content-length"] = str(len(body))
        return Response(
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
        )


def _allow_head(app: FastAPI) -> None:
    app.add_middleware(HeadMiddleware)


def _maybe_float(value) -> float | None:
    return None if value is None else float(value)


#: Module-level app for `uvicorn invest.api.app:app`.
app = create_app()
