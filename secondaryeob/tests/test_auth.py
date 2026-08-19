"""Access control tests (master prompt §2.2).

The point of these: enforcement is programmatic. A denial must happen in
the data-access path, so the caller gets an exception instead of bytes —
not a UI that declines to render something it already loaded.
"""

from __future__ import annotations

import json

import pytest

from secondaryeob.auth import Permission, Role, permissions_for, resolve_identity
from secondaryeob.auth.guard import Guard
from secondaryeob.errors import AuthenticationError, AuthorizationError, ConfigError
from secondaryeob.zones import Zone

PHI = b"Patient Name: Alder Quillfeather"


def test_reviewer_cannot_read_raw_phi(reviewer_guard: Guard, settings, vault):
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PHI, zone=Zone.A_RAW_PHI)

    with pytest.raises(AuthorizationError, match="READ_RAW_PHI"):
        reviewer_guard.read(path)


def test_biller_can_read_raw_phi(biller_guard: Guard, settings, vault):
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PHI, zone=Zone.A_RAW_PHI)
    assert biller_guard.read(path) == PHI


def test_admin_cannot_read_raw_phi(admin_guard: Guard, settings, vault):
    """Separation of duty: administering the system is not reading PHI."""
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PHI, zone=Zone.A_RAW_PHI)

    with pytest.raises(AuthorizationError):
        admin_guard.read(path)


def test_admin_cannot_export(admin_guard: Guard):
    with pytest.raises(AuthorizationError, match="EXPORT"):
        admin_guard.require(Permission.EXPORT)


def test_reviewer_can_approve_but_not_export(reviewer_guard: Guard):
    reviewer_guard.require(Permission.APPROVE)
    with pytest.raises(AuthorizationError, match="EXPORT"):
        reviewer_guard.require(Permission.EXPORT)


def test_path_outside_working_root_is_refused(biller_guard: Guard, tmp_path):
    outside = tmp_path / "elsewhere" / "secret.pdf"
    outside.parent.mkdir(parents=True, exist_ok=True)
    outside.write_bytes(b"x")

    with pytest.raises(AuthorizationError, match="outside the working root"):
        biller_guard.read(outside)


def test_traversal_out_of_zone_is_refused(biller_guard: Guard, settings, tmp_path):
    escape = settings.path_for("Ready") / ".." / ".." / "escape.pdf"
    with pytest.raises(AuthorizationError):
        biller_guard.read(escape)


def test_denials_are_audited(reviewer_guard: Guard, settings, vault, audit_log):
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PHI, zone=Zone.A_RAW_PHI)

    with pytest.raises(AuthorizationError):
        reviewer_guard.read(path)

    denials = [e for e in audit_log.verify_chain() if e.action == "ACCESS_DENIED"]
    assert len(denials) == 1
    assert denials[0].outcome == "BLOCKED"
    assert denials[0].detail["permission"] == "READ_RAW_PHI"


def test_grants_are_audited(biller_guard: Guard, settings, vault, audit_log):
    """A log that only records failures cannot answer 'who read this file'."""
    path = settings.path_for("Incoming") / "bulk.pdf"
    vault.write(path, PHI, zone=Zone.A_RAW_PHI)
    biller_guard.read(path)

    grants = [e for e in audit_log.verify_chain() if e.action == "ACCESS_GRANTED"]
    assert len(grants) == 1
    assert grants[0].role == "BILLER"


def test_role_permission_matrix():
    assert Permission.READ_RAW_PHI in permissions_for(Role.BILLER)
    assert Permission.READ_RAW_PHI not in permissions_for(Role.REVIEWER)
    assert Permission.READ_RAW_PHI not in permissions_for(Role.ADMIN)
    assert Permission.EXPORT not in permissions_for(Role.ADMIN)
    assert Permission.EXPORT not in permissions_for(Role.REVIEWER)


def test_unknown_account_gets_no_role(working_root):
    config_dir = working_root / "config"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "role_assignments.json").write_text(
        json.dumps({"posix:99999:nobody": "ADMIN"}), encoding="utf-8"
    )

    with pytest.raises(AuthenticationError, match="no role assignment"):
        resolve_identity(config_dir)


def test_missing_role_file_is_a_config_error(working_root):
    config_dir = working_root / "config"
    config_dir.mkdir(parents=True, exist_ok=True)
    with pytest.raises(ConfigError, match="no role assignments"):
        resolve_identity(config_dir)


def test_resolves_assigned_role(role_config):
    principal = resolve_identity(role_config)
    assert principal.role is Role.BILLER
    assert principal.has(Permission.READ_RAW_PHI)
