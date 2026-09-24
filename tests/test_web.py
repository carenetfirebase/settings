"""The built web app, served under /app.

None of these need a database: they exercise routing, file serving and
headers against a throwaway build directory.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from invest.api.app import create_app
from invest.api.web import CONTENT_SECURITY_POLICY

INDEX = "<!doctype html><title>invest</title><div id=root></div>"


@pytest.fixture
def dist(tmp_path: Path) -> Path:
    site = tmp_path / "dist"
    (site / "assets").mkdir(parents=True)
    (site / "index.html").write_text(INDEX)
    (site / "assets" / "index-abc123.js").write_text("console.log('ok')")
    # A file outside the build that a traversal attempt would try to reach.
    (tmp_path / "secret.txt").write_text("do not serve")
    return site


@pytest.fixture
def client(dist: Path) -> TestClient:
    return TestClient(create_app(web_dist=dist), follow_redirects=False)


def test_root_redirects_to_the_site(client: TestClient) -> None:
    response = client.get("/")
    assert response.status_code == 307
    assert response.headers["location"] == "/app/"


@pytest.mark.parametrize("path", ["/app", "/app/", "/app/research/NVDA", "/app/lab/calibration"])
def test_every_site_path_serves_the_app_shell(client: TestClient, path: str) -> None:
    """Deep links must survive a reload: the browser-side router handles them."""
    response = client.get(path)
    assert response.status_code == 200
    assert response.text == INDEX
    assert response.headers["cache-control"] == "no-cache"


def test_hashed_assets_are_served_and_cached(client: TestClient) -> None:
    response = client.get("/app/assets/index-abc123.js")
    assert response.status_code == 200
    assert response.text == "console.log('ok')"
    assert "javascript" in response.headers["content-type"]
    assert "immutable" in response.headers["cache-control"]


@pytest.mark.parametrize(
    "path", ["/app/../secret.txt", "/app/%2e%2e/secret.txt", "/app/assets/../../secret.txt"]
)
def test_paths_cannot_escape_the_build(client: TestClient, path: str) -> None:
    response = client.get(path)
    assert "do not serve" not in response.text


def test_security_headers_on_every_site_response(client: TestClient) -> None:
    for path in ("/app/", "/app/assets/index-abc123.js"):
        headers = client.get(path).headers
        assert headers["content-security-policy"] == CONTENT_SECURITY_POLICY
        assert headers["x-content-type-options"] == "nosniff"
        assert headers["referrer-policy"] == "no-referrer"


def test_policy_allows_nothing_from_third_parties() -> None:
    assert "http" not in CONTENT_SECURITY_POLICY
    assert "*" not in CONTENT_SECURITY_POLICY
    assert "script-src 'self'" in CONTENT_SECURITY_POLICY


def test_unbuilt_site_explains_how_to_build(tmp_path: Path) -> None:
    client = TestClient(create_app(web_dist=tmp_path / "missing"))
    response = client.get("/app/")
    assert response.status_code == 503
    assert "npm --prefix web run build" in response.text


def test_head_is_answered_for_site_paths(client: TestClient) -> None:
    response = client.head("/app/research/NVDA")
    assert response.status_code == 200
    assert response.content == b""


def test_site_routes_are_read_only_and_off_the_contract(client: TestClient) -> None:
    """Serving the site must not widen the API or add noise to its contract."""
    for method in ("post", "put", "patch", "delete"):
        assert getattr(client, method)("/app/").status_code == 405
    paths = client.get("/openapi.json").json()["paths"]
    assert not any(p == "/" or p.startswith("/app") for p in paths)
