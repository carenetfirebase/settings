"""Token-bucket rate limiter.

SEC EDGAR enforces a hard 10 requests/second ceiling and blocks offenders by
IP. We run at 8 rps to leave headroom for clock skew and for any other process
on the same address.

Deliberately simple and synchronous: the ingestion pipeline is single-threaded,
and a lock-protected bucket is easier to reason about than an async scheduler.
"""

from __future__ import annotations

import threading
import time


class TokenBucket:
    """Classic token bucket. `acquire()` blocks until a token is available."""

    def __init__(self, rate_per_second: float, capacity: float | None = None) -> None:
        if rate_per_second <= 0:
            raise ValueError("rate_per_second must be positive")
        self.rate = float(rate_per_second)
        # A burst equal to one second of traffic: enough to absorb jitter,
        # small enough that we never exceed the published ceiling over any
        # rolling second.
        self.capacity = float(capacity if capacity is not None else rate_per_second)
        self._tokens = self.capacity
        self._last = time.monotonic()
        self._lock = threading.Lock()

    def _refill(self, now: float) -> None:
        elapsed = now - self._last
        if elapsed <= 0:
            return
        self._tokens = min(self.capacity, self._tokens + elapsed * self.rate)
        self._last = now

    def acquire(self, tokens: float = 1.0, *, sleep=time.sleep) -> float:
        """Block until `tokens` are available. Returns seconds actually waited."""
        if tokens > self.capacity:
            raise ValueError("requested more tokens than bucket capacity")
        waited = 0.0
        while True:
            with self._lock:
                now = time.monotonic()
                self._refill(now)
                if self._tokens >= tokens:
                    self._tokens -= tokens
                    return waited
                deficit = tokens - self._tokens
                delay = deficit / self.rate
            sleep(delay)
            waited += delay
