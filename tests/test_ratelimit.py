"""Token bucket. Uses an injected fake clock/sleep so the tests are instant
and deterministic rather than actually waiting on wall time.
"""

from __future__ import annotations

import pytest

from invest.providers.ratelimit import TokenBucket


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


@pytest.fixture
def clock(monkeypatch) -> FakeClock:
    fake = FakeClock()
    monkeypatch.setattr("invest.providers.ratelimit.time.monotonic", fake.monotonic)
    return fake


def test_initial_burst_is_free(clock) -> None:
    bucket = TokenBucket(rate_per_second=8.0)
    for _ in range(8):
        assert bucket.acquire(sleep=clock.sleep) == 0.0


def test_exhausted_bucket_forces_a_wait(clock) -> None:
    bucket = TokenBucket(rate_per_second=8.0)
    for _ in range(8):
        bucket.acquire(sleep=clock.sleep)

    waited = bucket.acquire(sleep=clock.sleep)
    assert waited == pytest.approx(1 / 8, rel=1e-6)


def test_sustained_rate_never_exceeds_the_ceiling(clock) -> None:
    """The property that actually matters: EDGAR's 10 req/s ceiling is a hard
    block, so 40 requests at 8 rps must take at least ~4 seconds of clock.
    """
    bucket = TokenBucket(rate_per_second=8.0)
    start = clock.now
    for _ in range(40):
        bucket.acquire(sleep=clock.sleep)
    elapsed = clock.now - start

    # 40 requests, 8/s, minus the free initial burst of 8.
    assert elapsed == pytest.approx((40 - 8) / 8, rel=1e-6)
    assert 40 / max(elapsed, 1e-9) <= 10.0


def test_tokens_refill_over_time(clock) -> None:
    bucket = TokenBucket(rate_per_second=8.0)
    for _ in range(8):
        bucket.acquire(sleep=clock.sleep)

    clock.now += 1.0  # a full second passes
    assert bucket.acquire(sleep=clock.sleep) == 0.0


def test_refill_is_capped_at_capacity(clock) -> None:
    bucket = TokenBucket(rate_per_second=8.0)
    clock.now += 100.0  # idle for a long time
    for _ in range(8):
        assert bucket.acquire(sleep=clock.sleep) == 0.0
    # Capacity is one second of traffic — the 9th must still wait.
    assert bucket.acquire(sleep=clock.sleep) > 0


def test_rejects_impossible_request(clock) -> None:
    bucket = TokenBucket(rate_per_second=8.0)
    with pytest.raises(ValueError, match="capacity"):
        bucket.acquire(100, sleep=clock.sleep)


def test_rejects_non_positive_rate() -> None:
    with pytest.raises(ValueError, match="positive"):
        TokenBucket(rate_per_second=0)
