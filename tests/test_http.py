"""The single outbound HTTP path.

Everything here is about what the client *refuses* to do. The guarantees are
only worth anything if they cannot be bypassed by an adapter that is in a
hurry.
"""

from __future__ import annotations

from pathlib import Path

import httpx
import pytest

from imt.core.config import Settings
from imt.core.http import (
    ForbiddenHostError,
    HostNotDeclaredError,
    HttpClient,
    SourceNotEnabledError,
)


def _client(handler, tmp_path: Path) -> HttpClient:
    return HttpClient(
        Settings(IMT_SEC_CONTACT="tests@example.com"),
        transport=httpx.MockTransport(handler),
        cache_dir=tmp_path / "cache",
        sleep=lambda _s: None,
    )


def test_attaches_a_contact_bearing_user_agent(tmp_path: Path) -> None:
    """The SEC blocks IPs whose User-Agent has no contact address."""
    seen: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(request.headers)
        return httpx.Response(200, content=b"{}")

    with _client(handler, tmp_path) as client:
        client.get("sec_edgar", "https://data.sec.gov/submissions/CIK0000320193.json")
    assert "tests@example.com" in seen["user-agent"]
    assert seen["user-agent"].startswith("Informed Money Terminal")


def test_refuses_a_host_not_declared_for_the_source(tmp_path: Path) -> None:
    """Adding a host means editing config/sources.yaml, which is reviewable."""
    with _client(lambda r: httpx.Response(200), tmp_path) as client:
        with pytest.raises(HostNotDeclaredError, match="not declared"):
            client.get("sec_edgar", "https://example.com/data.json")


def test_refuses_a_host_on_the_do_not_automate_list(tmp_path: Path) -> None:
    """docs/DATA_SOURCES.md 'Explicitly not automated'.

    These sites may be used for manual verification and must never become code
    dependencies. Promoting one is a decision with terms of service attached.
    """
    with _client(lambda r: httpx.Response(200), tmp_path) as client:
        with pytest.raises(ForbiddenHostError, match="do-not-automate"):
            client.get("sec_edgar", "https://openinsider.com/latest")


def test_refuses_a_disabled_source(tmp_path: Path) -> None:
    """A source awaiting a free API key must fail loudly, not silently no-op."""
    with _client(lambda r: httpx.Response(200), tmp_path) as client:
        with pytest.raises(SourceNotEnabledError, match="awaiting_api_key"):
            client.get("sam_gov", "https://api.sam.gov/opportunities/v2/search")


def test_sec_403_is_not_retried(tmp_path: Path) -> None:
    """A 403 from the SEC means the IP is blocked. Retrying digs the hole deeper."""
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(403, content=b"denied")

    with _client(handler, tmp_path) as client:
        with pytest.raises(PermissionError, match="blocked"):
            client.get("sec_edgar", "https://data.sec.gov/submissions/CIK1.json")
    assert calls["n"] == 1


def test_retries_a_429_then_succeeds(tmp_path: Path) -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] < 3:
            return httpx.Response(429)
        return httpx.Response(200, content=b'{"ok":true}')

    with _client(handler, tmp_path) as client:
        response = client.get("sec_edgar", "https://data.sec.gov/x.json")
    assert response.json() == {"ok": True}
    assert calls["n"] == 3


def test_second_request_is_served_from_cache(tmp_path: Path) -> None:
    """A restarted backfill replays from disk instead of re-hammering a source."""
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, content=b"payload")

    with _client(handler, tmp_path) as client:
        first = client.get("stooq", "https://stooq.com/q/d/l/?s=aapl.us&i=d")
        second = client.get("stooq", "https://stooq.com/q/d/l/?s=aapl.us&i=d")

    assert calls["n"] == 1
    assert first.from_cache is False
    assert second.from_cache is True
    assert second.body == b"payload"


def test_missing_sec_contact_fails_before_any_request(tmp_path: Path) -> None:
    """Better to stop than to send a request that earns an IP ban."""
    client = HttpClient(
        Settings(IMT_SEC_CONTACT=""),
        transport=httpx.MockTransport(lambda r: httpx.Response(200)),
        cache_dir=tmp_path / "cache",
    )
    with client, pytest.raises(ValueError, match="IMT_SEC_CONTACT"):
        client.get("sec_edgar", "https://data.sec.gov/x.json")
