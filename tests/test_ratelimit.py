"""Rate limiting. The SEC bans IPs; this is the code that stops that happening."""

from __future__ import annotations

import time

import pytest

from imt.core.ratelimit import LimiterRegistry, RateLimiter


class FakeClock:
    """Virtual time, so the test measures scheduling rather than wall clock."""

    def __init__(self) -> None:
        self.now = 0.0
        self.slept = 0.0

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds
        self.slept += seconds


def test_phase1_criterion_6_twenty_requests_at_8_per_second() -> None:
    """docs/PHASES.md Phase 1 #6: 20 queued requests take at least 2.4s at 8/s.

    At a strict 0.125s spacing with the bucket starting empty, the twentieth
    request lands at 20 x 0.125 = 2.5s.
    """
    clock = FakeClock()
    limiter = RateLimiter(8.0, monotonic=clock.monotonic, sleep=clock.sleep)
    start = clock.now
    for _ in range(20):
        limiter.acquire()
    elapsed = clock.now - start
    assert elapsed >= 2.4, f"20 requests at 8/s took {elapsed:.3f}s, expected >= 2.4s"
    assert elapsed == pytest.approx(2.5, abs=0.01)


def test_bucket_starts_empty_so_a_restart_loop_cannot_burst() -> None:
    """A token bucket that starts full lets each fresh process fire a burst.

    Bans are per-IP and outlive the process, so a crash-restart loop could
    issue bursts indefinitely while every individual process looked polite.
    """
    clock = FakeClock()
    limiter = RateLimiter(8.0, monotonic=clock.monotonic, sleep=clock.sleep)
    limiter.acquire()
    assert clock.slept == pytest.approx(0.125)


def test_interval_is_the_reciprocal_of_the_rate() -> None:
    assert RateLimiter(8.0).interval == pytest.approx(0.125)
    assert RateLimiter(0.5).interval == pytest.approx(2.0)


def test_rejects_a_nonsense_rate() -> None:
    with pytest.raises(ValueError, match="positive"):
        RateLimiter(0)


def test_registry_returns_one_limiter_per_host() -> None:
    registry = LimiterRegistry()
    a = registry.for_host("data.sec.gov", 8.0)
    b = registry.for_host("data.sec.gov", 8.0)
    c = registry.for_host("stooq.com", 0.5)
    assert a is b
    assert a is not c


def test_real_clock_actually_spaces_requests() -> None:
    """One test against the real clock, so the fake cannot hide a mistake."""
    limiter = RateLimiter(50.0)
    start = time.monotonic()
    for _ in range(5):
        limiter.acquire()
    assert time.monotonic() - start >= 0.09
