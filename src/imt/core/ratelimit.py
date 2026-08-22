"""Per-host request spacing.

The SEC's fair-access rule is a hard ceiling of 10 requests/second, and
exceeding it gets the IP blocked — not throttled, blocked, at the network edge,
for everyone on that address. So this is a strict-spacing limiter rather than a
token bucket: it enforces a minimum interval between requests instead of
allowing a burst up to some capacity.

Two consequences worth stating, because they look like bugs otherwise:

1. **The bucket starts empty.** A freshly-started process waits one interval
   before its first request. A token bucket that starts full would let a job
   fire 8 requests instantly, and since bans are per-IP and outlive the
   process, a crash-restart loop could issue bursts indefinitely while every
   individual process believed it was well-behaved.
2. **It is never faster than ``1/rate`` per call.** That is the point. Ingest
   jobs are I/O bound by design; throughput comes from running them on a
   schedule, not from concurrency.
"""

from __future__ import annotations

import threading
import time
from collections.abc import Callable


class RateLimiter:
    """Strict-spacing limiter for one host.

    Thread-safe. ``acquire`` blocks until the caller's reserved slot arrives.
    Slots are reserved in call order, so concurrent callers are served fairly
    rather than starving each other.
    """

    def __init__(
        self,
        rate_per_second: float,
        *,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if rate_per_second <= 0:
            raise ValueError("rate_per_second must be positive")
        self._interval = 1.0 / rate_per_second
        self._monotonic = monotonic
        self._sleep = sleep
        self._lock = threading.Lock()
        # Start one interval in the future: see note 1 in the module docstring.
        self._next_slot = monotonic() + self._interval

    @property
    def interval(self) -> float:
        return self._interval

    def acquire(self) -> float:
        """Block until this caller's slot. Returns how long it waited."""
        with self._lock:
            slot = self._next_slot
            self._next_slot = slot + self._interval
        wait = slot - self._monotonic()
        if wait > 0:
            self._sleep(wait)
            return wait
        return 0.0


class LimiterRegistry:
    """One limiter per host, created on first use."""

    def __init__(self) -> None:
        self._limiters: dict[str, RateLimiter] = {}
        self._lock = threading.Lock()

    def for_host(self, host: str, rate_per_second: float) -> RateLimiter:
        key = host.lower()
        with self._lock:
            limiter = self._limiters.get(key)
            if limiter is None:
                limiter = RateLimiter(rate_per_second)
                self._limiters[key] = limiter
            return limiter

    def reset(self) -> None:
        with self._lock:
            self._limiters.clear()
