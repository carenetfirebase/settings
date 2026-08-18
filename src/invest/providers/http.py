"""Shared HTTP plumbing for providers: retries, rate limiting, honest errors.

Retries only on transport errors and 5xx/429 — never on a 4xx, which means we
asked for something that does not exist and retrying would just be noise.
"""

from __future__ import annotations

import logging
import time
from typing import Self

import httpx

from invest.providers.base import ProviderUnavailable
from invest.providers.ratelimit import TokenBucket

logger = logging.getLogger(__name__)

RETRY_STATUS = frozenset({429, 500, 502, 503, 504})


class HttpClient:
    """Thin wrapper over httpx with a token bucket and bounded backoff."""

    def __init__(
        self,
        *,
        source_name: str,
        user_agent: str,
        rate_per_second: float = 5.0,
        timeout: float = 30.0,
        max_attempts: int = 4,
        client: httpx.Client | None = None,
    ) -> None:
        self.source_name = source_name
        self.bucket = TokenBucket(rate_per_second)
        self.max_attempts = max_attempts
        self._client = client or httpx.Client(
            timeout=timeout,
            headers={"User-Agent": user_agent, "Accept-Encoding": "gzip, deflate"},
            follow_redirects=True,
        )

    def get(self, url: str, *, params: dict | None = None) -> httpx.Response:
        last_error: Exception | None = None

        for attempt in range(1, self.max_attempts + 1):
            self.bucket.acquire()
            try:
                response = self._client.get(url, params=params)
            except httpx.HTTPError as exc:
                last_error = exc
                logger.warning(
                    "%s: transport error on %s (attempt %d/%d): %s",
                    self.source_name,
                    url,
                    attempt,
                    self.max_attempts,
                    exc,
                )
            else:
                if response.status_code in RETRY_STATUS:
                    last_error = ProviderUnavailable(
                        f"{self.source_name}: HTTP {response.status_code} for {url}"
                    )
                    logger.warning(
                        "%s: HTTP %d on %s (attempt %d/%d)",
                        self.source_name,
                        response.status_code,
                        url,
                        attempt,
                        self.max_attempts,
                    )
                elif response.status_code >= 400:
                    # A 404 is an answer, not a hiccup. Do not retry.
                    raise ProviderUnavailable(
                        f"{self.source_name}: HTTP {response.status_code} for {url}"
                    )
                else:
                    return response

            if attempt < self.max_attempts:
                time.sleep(min(2 ** (attempt - 1), 8))

        raise ProviderUnavailable(
            f"{self.source_name}: giving up on {url} after {self.max_attempts} attempts"
        ) from last_error

    def stream_to_file(self, url: str, destination: str, *, chunk_bytes: int = 1 << 20) -> int:
        """Download a large body straight to disk, returning bytes written.

        Bulk archives run to gigabytes; buffering one in memory to then write
        it out would be a needless way to exhaust a laptop. Not retried: a
        partial multi-gigabyte download is better resumed deliberately than
        silently restarted from zero.
        """
        import pathlib

        path = pathlib.Path(destination)
        path.parent.mkdir(parents=True, exist_ok=True)

        self.bucket.acquire()
        written = 0
        try:
            with self._client.stream("GET", url) as response:
                if response.status_code >= 400:
                    raise ProviderUnavailable(
                        f"{self.source_name}: HTTP {response.status_code} for {url}"
                    )
                with path.open("wb") as handle:
                    for chunk in response.iter_bytes(chunk_bytes):
                        handle.write(chunk)
                        written += len(chunk)
        except httpx.HTTPError as exc:
            raise ProviderUnavailable(
                f"{self.source_name}: transport error streaming {url}: {exc}"
            ) from exc
        return written

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()
