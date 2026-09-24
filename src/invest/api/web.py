"""Serve the built web app under /app.

The site (`web/`, built with `npm --prefix web run build`) is a single-page
app, so every `/app/...` path that is not a real file answers with
`index.html` and the browser-side router takes it from there. That is what
lets a deep link like `/app/research/NVDA` survive a reload.

What this module does **not** do is widen the API. It adds GET routes only,
excluded from the OpenAPI contract, and the site reads data through the same
read-only endpoints as everyone else. The existing structural tests (every
route is a GET, the contract declares only GET) still hold.

Headers:

* `index.html` is served `no-cache`, so a rebuilt site is picked up on reload.
* Hashed files under `assets/` never change content, so they are cached for a
  year.
* A Content-Security-Policy restricts the page to this origin. The site loads
  nothing from third parties, and the policy makes that a guarantee rather
  than a habit. This matters more once the site can place orders.
"""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response

WEB_PREFIX = "/app"

#: Environment variable that points at a built site somewhere else.
DIST_ENV = "INVEST_WEB_DIST"

CONTENT_SECURITY_POLICY = (
    "default-src 'self'; "
    "script-src 'self'; "
    # React writes `style` attributes for chart sizing and bar widths.
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data:; "
    "connect-src 'self'; "
    "font-src 'self'; "
    "object-src 'none'; "
    "base-uri 'none'; "
    "frame-ancestors 'none'; "
    "form-action 'self'"
)

SECURITY_HEADERS = {
    "Content-Security-Policy": CONTENT_SECURITY_POLICY,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
}

NOT_BUILT_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Site not built</title>
<style>body{font:15px/1.5 system-ui,sans-serif;background:#0b0d10;color:#f2f3f5;
display:grid;place-items:center;min-height:100vh;margin:0}main{max-width:560px;padding:24px}
code{background:#1f232a;padding:2px 6px;border-radius:4px}</style></head>
<body><main><h1>The web app has not been built yet</h1>
<p>From the repository root, run:</p>
<p><code>npm --prefix web install</code><br><code>npm --prefix web run build</code></p>
<p>then reload this page. The research API itself is running: see <a href="/docs"
style="color:#3987e5">/docs</a>.</p></main></body></html>
"""


def default_dist_dir() -> Path:
    """`$INVEST_WEB_DIST` if set, else `web/dist` in the repository checkout."""
    configured = os.environ.get(DIST_ENV)
    if configured:
        return Path(configured)
    # src/invest/api/web.py -> repository root is three levels above `invest`.
    return Path(__file__).resolve().parents[3] / "web" / "dist"


def _resolve_inside(root: Path, relative: str) -> Path | None:
    """The file `relative` names under `root`, or None if it escapes or is absent."""
    if not relative:
        return None
    root = root.resolve()
    candidate = (root / relative).resolve()
    if candidate != root and root not in candidate.parents:
        return None
    return candidate if candidate.is_file() else None


def mount_web(app: FastAPI, dist_dir: Path | None = None) -> None:
    """Register the /app routes. The build is looked up per request, so a site
    built after the server started is served without a restart.
    """
    dist = dist_dir if dist_dir is not None else default_dist_dir()

    def serve(path: str) -> Response:
        index = dist / "index.html"
        if not index.is_file():
            return HTMLResponse(NOT_BUILT_PAGE, status_code=503, headers=SECURITY_HEADERS)

        asset = _resolve_inside(dist, path)
        if asset is not None:
            immutable = asset.parent.name == "assets"
            headers = {
                **SECURITY_HEADERS,
                "Cache-Control": "public, max-age=31536000, immutable" if immutable else "no-cache",
            }
            return FileResponse(asset, headers=headers)

        return FileResponse(index, headers={**SECURITY_HEADERS, "Cache-Control": "no-cache"})

    @app.get("/", include_in_schema=False)
    def root() -> RedirectResponse:
        return RedirectResponse(f"{WEB_PREFIX}/")

    @app.get(WEB_PREFIX, include_in_schema=False)
    def web_index() -> Response:
        return serve("")

    @app.get(WEB_PREFIX + "/{path:path}", include_in_schema=False)
    def web_path(path: str) -> Response:
        return serve(path)
