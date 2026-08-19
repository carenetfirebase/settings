"""Deployment-safety and PHI lifecycle tests (master prompt §1.2, §5)."""

from __future__ import annotations

import os
import time
from pathlib import Path

import pytest

from secondaryeob.config import load_settings
from secondaryeob.errors import (
    ConfigError,
    DeletionVerificationError,
    UnsafeWorkingDirectoryError,
)
from secondaryeob.lifecycle import purge_expired, verified_delete
from secondaryeob.zones import Zone


# --- refusing unsafe deployments ---------------------------------------


@pytest.mark.parametrize(
    "folder", ["OneDrive", "Dropbox", "Google Drive", "iCloud Drive", "Box Sync"]
)
def test_sync_folder_root_is_refused(tmp_path, monkeypatch, folder):
    root = tmp_path / folder / "seob"
    root.mkdir(parents=True)
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(root))

    with pytest.raises(UnsafeWorkingDirectoryError, match="file-sync folder"):
        load_settings()


def test_sync_sentinel_file_is_detected(tmp_path, monkeypatch):
    """A renamed sync folder is still caught by its sentinel file."""
    parent = tmp_path / "CompanyFiles"
    root = parent / "seob"
    root.mkdir(parents=True)
    (parent / ".dropbox").write_text("")
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(root))

    with pytest.raises(UnsafeWorkingDirectoryError):
        load_settings()


def test_missing_root_is_refused(monkeypatch):
    monkeypatch.delenv("SECONDARYEOB_ROOT", raising=False)
    with pytest.raises(ConfigError, match="Refusing to guess"):
        load_settings()


def test_encryption_cannot_be_disabled_outside_dev_mode(tmp_path, monkeypatch):
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(tmp_path / "seob"))
    monkeypatch.setenv("SECONDARYEOB_ENCRYPTION", "0")
    monkeypatch.delenv("SECONDARYEOB_DEV_MODE", raising=False)

    with pytest.raises(ConfigError, match="cannot be disabled"):
        load_settings()


def test_encryption_may_be_disabled_in_dev_mode(tmp_path, monkeypatch):
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(tmp_path / "seob"))
    monkeypatch.setenv("SECONDARYEOB_ENCRYPTION", "0")
    monkeypatch.setenv("SECONDARYEOB_DEV_MODE", "1")

    settings = load_settings()
    assert settings.encryption_enabled is False
    assert settings.development_mode is True


def test_defaults_are_loopback_only(settings):
    assert settings.api_host == "127.0.0.1"


def test_public_bind_is_refused_without_acknowledgement(tmp_path, monkeypatch):
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(tmp_path / "seob"))
    monkeypatch.setenv("SECONDARYEOB_API_HOST", "0.0.0.0")
    monkeypatch.delenv("SECONDARYEOB_ALLOW_PUBLIC_BIND", raising=False)

    with pytest.raises(ConfigError, match="TLS"):
        load_settings()


def test_zone_directories_are_created(settings):
    settings.ensure_directories()
    for name in ("Incoming", "Working", "Ready", "Quarantine", "Logs"):
        assert settings.path_for(name).is_dir()


# --- deletion verification (§5.2) --------------------------------------


def test_verified_delete_removes_the_file(tmp_path):
    path = tmp_path / "phi.enc"
    path.write_bytes(b"ciphertext")
    verified_delete(path)
    assert not path.exists()


def test_verified_delete_is_idempotent(tmp_path):
    verified_delete(tmp_path / "never-existed.enc")


def test_verified_delete_reports_a_surviving_file(tmp_path, monkeypatch):
    """Deletion that silently fails must raise, not report success."""
    path = tmp_path / "phi.enc"
    path.write_bytes(b"ciphertext")

    monkeypatch.setattr(Path, "unlink", lambda self, missing_ok=False: None)
    with pytest.raises(DeletionVerificationError, match="still exists"):
        verified_delete(path)


# --- retention (§5.1) --------------------------------------------------


def _age(path: Path, seconds: int) -> None:
    old = time.time() - seconds
    os.utime(path, (old, old))


def test_expired_working_files_are_purged(settings, vault, admin_guard):
    working = settings.path_for("Working")
    fresh = working / "fresh.enc"
    stale = working / "stale.enc"
    vault.write(fresh, b"a", zone=Zone.B_PROCESSING)
    vault.write(stale, b"b", zone=Zone.B_PROCESSING)
    _age(stale, (settings.working_retention_hours + 1) * 3600)

    report = purge_expired(admin_guard, settings)

    assert report.clean
    assert report.deleted == 1
    assert fresh.exists()
    assert not stale.exists()


def test_expired_quarantine_is_purged(settings, vault, admin_guard):
    quarantine = settings.path_for("Quarantine")
    stale = quarantine / "old.enc"
    vault.write(stale, b"x", zone=Zone.A_RAW_PHI)
    _age(stale, (settings.quarantine_retention_days + 1) * 86400)

    report = purge_expired(admin_guard, settings)
    assert report.deleted == 1
    assert not stale.exists()


def test_purge_requires_permission(settings, biller_guard):
    from secondaryeob.errors import AuthorizationError

    with pytest.raises(AuthorizationError, match="PURGE"):
        purge_expired(biller_guard, settings)


def test_each_deletion_is_audited(settings, vault, admin_guard, audit_log):
    stale = settings.path_for("Working") / "stale.enc"
    vault.write(stale, b"b", zone=Zone.B_PROCESSING)
    _age(stale, (settings.working_retention_hours + 1) * 3600)

    purge_expired(admin_guard, settings)

    deletions = [e for e in audit_log.verify_chain() if e.action == "DELETE"]
    assert len(deletions) == 1
    assert deletions[0].detail["reason"] == "retention_expiry"


def test_expired_intake_is_purged(settings, vault, admin_guard):
    """Raw intake must not accumulate: processing does not consume it."""
    incoming = settings.path_for("Incoming")
    fresh = incoming / "today.enc"
    stale = incoming / "last-week.enc"
    vault.write(fresh, b"a", zone=Zone.A_RAW_PHI)
    vault.write(stale, b"b", zone=Zone.A_RAW_PHI)
    _age(stale, (settings.incoming_retention_hours + 1) * 3600)

    report = purge_expired(admin_guard, settings)

    assert report.clean
    assert fresh.exists()
    assert not stale.exists()


def test_ready_output_is_not_purged(settings, vault, admin_guard):
    """Retention covers working and quarantine, not approved output."""
    ready = settings.path_for("Ready") / "approved.enc"
    vault.write(ready, b"sanitized", zone=Zone.C_SANITIZED)
    _age(ready, 90 * 86400)

    purge_expired(admin_guard, settings)
    assert ready.exists()
