"""Session assembly — the one place the controls are wired together.

Opening a session is the moment every control is proven live: the working
root is checked, the audit chain is verified, the key is unwrapped, and
the identity is resolved to a role. If any of those fails the session does
not open, so there is no partially-controlled state in which the pipeline
can run.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .audit import Action, AuditLog, Outcome
from .auth import Guard, Principal, resolve_identity
from .config import Settings, load_settings
from .crypto import Keyring, Vault

_CONFIG_DIRNAME = "config"
_KEYS_DIRNAME = "keys"
_AUDIT_FILENAME = "audit.jsonl"


@dataclass
class Session:
    """An authenticated, audited, encrypted working session."""

    settings: Settings
    principal: Principal
    guard: Guard
    audit: AuditLog
    vault: Vault

    def close(self) -> None:
        self.guard.record(Action.SYSTEM, outcome=Outcome.SUCCESS, detail={"event": "session_close"})


def open_session(working_root: Path | str | None = None) -> Session:
    """Open a session, enforcing every startup control.

    Raises:
        UnsafeWorkingDirectoryError: root is inside a file-sync folder.
        AuditIntegrityError: the audit chain does not verify.
        AuthenticationError: the OS account has no role assignment.
        EncryptionError: the data encryption key could not be unwrapped.
    """
    settings = load_settings(working_root)
    settings.ensure_directories()

    config_dir = settings.working_root / _CONFIG_DIRNAME
    config_dir.mkdir(parents=True, exist_ok=True)

    # Verified before anything else can append to it.
    audit = AuditLog.open(settings.path_for("Logs") / _AUDIT_FILENAME)

    keyring = Keyring.for_platform(
        settings.working_root / _KEYS_DIRNAME,
        passphrase_env_var=settings.passphrase_env_var,
    )
    vault = Vault(keyring.load_or_create(), enabled=settings.encryption_enabled)

    principal = resolve_identity(config_dir)

    guard = Guard(principal, vault, audit, settings.working_root)
    guard.record(
        Action.AUTH,
        outcome=Outcome.SUCCESS,
        detail={
            "event": "session_open",
            "key_provider": keyring.provider_name,
            "encryption": settings.encryption_enabled,
            "audit_entries_verified": audit.entry_count,
        },
    )

    return Session(
        settings=settings, principal=principal, guard=guard, audit=audit, vault=vault
    )
