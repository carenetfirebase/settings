"""Shared fixtures.

Tests never hit the network (CLAUDE.md). ``respx`` mocks HTTP; anything that
escapes the mock is a test bug, and ``no_network`` below turns it into a loud
failure rather than a slow one.
"""

from __future__ import annotations

import socket
from collections.abc import Iterator
from pathlib import Path

import pytest

from imt.core.config import clear_config_cache


@pytest.fixture(autouse=True)
def _isolated_config(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Iterator[None]:
    monkeypatch.setenv("IMT_SEC_CONTACT", "tests@example.com")
    monkeypatch.setenv("IMT_CACHE_DIR", str(tmp_path / "http-cache"))
    clear_config_cache()
    yield
    clear_config_cache()


@pytest.fixture(autouse=True)
def no_network(request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch) -> None:
    """Make a real socket connection raise.

    Phase 1 criterion 4 requires the suite to pass with the network disabled.
    Rather than trusting that, this makes an accidental live call fail
    immediately and name itself.
    """
    if request.node.get_closest_marker("live"):
        return

    def guard(*args: object, **kwargs: object) -> None:
        raise RuntimeError(
            "A test tried to open a network connection. Tests use recorded "
            "fixtures in tests/fixtures/; live tests are marked @pytest.mark.live."
        )

    monkeypatch.setattr(socket.socket, "connect", guard)
    monkeypatch.setattr(socket, "create_connection", guard)


@pytest.fixture
def fixtures_dir() -> Path:
    return Path(__file__).parent / "fixtures"
