"""The only outbound HTTP path in the system.

No adapter constructs an ``httpx`` client. Everything goes through
:class:`HttpClient`, which is what makes four guarantees enforceable in one
place instead of thirteen:

* the host is declared in ``config/sources.yaml`` for the source being used,
  and is not on the forbidden list;
* a contact-bearing User-Agent is attached (the SEC bans IPs without one);
* the per-host rate limit is respected;
* responses are cached to disk so a restarted backfill replays instead of
  re-hammering the source.

A test asserts that no module under ``imt/adapters`` imports ``httpx``.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx

from imt.core.cache import CachedResponse, ResponseCache, cache_key
from imt.core.clock import utc_now
from imt.core.config import Settings, forbidden_hosts, get_settings, source_config
from imt.core.logging import get_logger
from imt.core.ratelimit import LimiterRegistry

log = get_logger(__name__)

RETRY_STATUS = frozenset({429, 500, 502, 503, 504})


class SourceNotEnabledError(RuntimeError):
    """The source exists but is disabled — usually awaiting a free API key."""


class HostNotDeclaredError(RuntimeError):
    """A request was attempted against a host not declared for this source."""


class ForbiddenHostError(RuntimeError):
    """A request was attempted against a host on the do-not-automate list."""


@dataclass(frozen=True, slots=True)
class Response:
    """What adapters receive. Deliberately not an ``httpx.Response``.

    Adapters get bytes and a retrieval timestamp; they do not get a live
    connection, a redirect history, or anything else that would tempt a second
    request outside this module.
    """

    status_code: int
    body: bytes
    url: str
    retrieved_at: Any
    from_cache: bool

    def text(self, encoding: str = "utf-8") -> str:
        return self.body.decode(encoding, errors="replace")

    def json(self) -> Any:
        import json

        return json.loads(self.body)


class HttpClient:
    def __init__(
        self,
        settings: Settings | None = None,
        *,
        transport: httpx.BaseTransport | None = None,
        cache_dir: Path | None = None,
        sleep: Any = time.sleep,
    ) -> None:
        self._settings = settings or get_settings()
        self._limiters = LimiterRegistry()
        self._cache = ResponseCache(cache_dir or self._settings.cache_dir)
        self._sleep = sleep
        self._client = httpx.Client(
            transport=transport, timeout=httpx.Timeout(30.0), follow_redirects=True
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> HttpClient:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _check_host(self, source_id: str, url: str, config: dict[str, Any]) -> str:
        host = (urlparse(url).hostname or "").lower()
        if not host:
            raise ValueError(f"Cannot determine host for URL: {url!r}")
        if host in forbidden_hosts():
            raise ForbiddenHostError(
                f"{host} is on the do-not-automate list in config/sources.yaml. "
                f"Adding it is a decision that needs its terms of service attached, "
                f"not a code change."
            )
        declared = {str(h).lower() for h in config.get("hosts", [])}
        if host not in declared:
            raise HostNotDeclaredError(
                f"Host {host!r} is not declared for source {source_id!r}. "
                f"Declared hosts: {sorted(declared) or '(none)'}. "
                f"Add it to config/sources.yaml in the same commit as the adapter."
            )
        return host

    def get(
        self,
        source_id: str,
        url: str,
        *,
        params: dict[str, Any] | None = None,
        max_age_seconds: float | None = None,
        max_retries: int = 4,
        allow_cache: bool = True,
    ) -> Response:
        config = source_config(source_id)
        if not config.get("enabled", False):
            raise SourceNotEnabledError(
                f"Source {source_id!r} is disabled in config/sources.yaml"
                + (f" ({config['blocked_reason']})" if config.get("blocked_reason") else "")
                + ". Build the interface, disable the feature, do not approximate it."
            )
        host = self._check_host(source_id, url, config)

        request = self._client.build_request("GET", url, params=params)
        full_url = str(request.url)
        headers = self._headers(config)
        key = cache_key("GET", full_url, headers.get("User-Agent", ""))

        if allow_cache:
            cached = self._cache.get(key, max_age_seconds=max_age_seconds)
            if cached is not None:
                log.debug("http.cache_hit", source=source_id, url=full_url)
                return Response(
                    status_code=cached.status_code,
                    body=cached.body,
                    url=cached.url,
                    retrieved_at=cached.retrieved_at,
                    from_cache=True,
                )

        limiter = self._limiters.for_host(host, float(config.get("rate_limit_per_second", 1.0)))
        last_error: Exception | None = None

        for attempt in range(max_retries):
            limiter.acquire()
            try:
                raw = self._client.get(full_url, headers=headers)
            except httpx.HTTPError as exc:
                last_error = exc
                self._backoff(attempt, source_id, full_url, reason=type(exc).__name__)
                continue

            if raw.status_code in RETRY_STATUS:
                last_error = httpx.HTTPStatusError(
                    f"HTTP {raw.status_code}", request=raw.request, response=raw
                )
                # 403 from the SEC means a ban, not a transient failure -- do not
                # retry into a deeper hole. 429/5xx are worth backing off on.
                self._backoff(attempt, source_id, full_url, reason=str(raw.status_code))
                continue

            if raw.status_code == 403 and host.endswith("sec.gov"):
                raise PermissionError(
                    "SEC returned 403. This usually means the IP is blocked for "
                    "exceeding 10 req/s or sending a User-Agent without a contact "
                    "address. Do not retry -- stop the job and check "
                    "IMT_SEC_CONTACT and the rate limit."
                )

            response = Response(
                status_code=raw.status_code,
                body=raw.content,
                url=full_url,
                retrieved_at=utc_now(),
                from_cache=False,
            )
            if allow_cache and raw.status_code == 200:
                self._cache.put(
                    key,
                    CachedResponse(
                        status_code=response.status_code,
                        body=response.body,
                        retrieved_at=response.retrieved_at,
                        url=full_url,
                    ),
                )
            return response

        raise RuntimeError(
            f"GET {full_url} failed after {max_retries} attempts: {last_error}"
        ) from last_error

    def _headers(self, config: dict[str, Any]) -> dict[str, str]:
        headers = {"Accept-Encoding": "gzip, deflate"}
        if config.get("requires_user_agent", True):
            headers["User-Agent"] = self._settings.user_agent()
        return headers

    def _backoff(self, attempt: int, source_id: str, url: str, *, reason: str) -> None:
        delay = 2.0**attempt
        log.warning(
            "http.retry", source=source_id, url=url, attempt=attempt + 1, reason=reason, delay=delay
        )
        self._sleep(delay)
