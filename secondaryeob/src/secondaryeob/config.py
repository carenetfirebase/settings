"""Environment-driven settings. No hardcoded secrets, no PHI.

Defaults are deliberately conservative: localhost-only, short retention,
encryption required. A deployment makes itself *less* safe only by
explicitly setting an environment variable to do so, and the two settings
that could create a compliance gap (network binding, encryption) refuse
to be loosened without an accompanying acknowledgement variable.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from .errors import ConfigError, UnsafeWorkingDirectoryError
from .zones import ZONE_DIRECTORIES

#: Directory names used by consumer file-sync clients. A working root
#: inside one of these is refused outright (plan §F): the sync client runs
#: in another process, copies PHI off the machine, and honours none of
#: this application's controls.
_SYNC_CLIENT_MARKERS = frozenset(
    {
        "onedrive",
        "onedrive - personal",
        "dropbox",
        "google drive",
        "googledrive",
        "my drive",
        "icloud drive",
        "iclouddrive",
        "com~apple~clouddocs",
        "box",
        "box sync",
        "pcloud",
        "mega",
        "megasync",
        "sync.com",
        "tresorit",
        "nextcloud",
        "owncloud",
        "creative cloud files",
    }
)

#: Files a sync client drops in a folder it manages. Checked in addition
#: to the name list because corporate deployments rename the folder.
_SYNC_CLIENT_SENTINELS = frozenset(
    {".dropbox", ".dropbox.cache", ".onedrive", ".csync_journal.db", ".nextcloudsync.log"}
)


def _env_flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer, got {raw!r}") from exc


def _looks_like_sync_folder(root: Path) -> str | None:
    """Return the offending path component if ``root`` is inside a sync folder."""
    resolved = root.resolve()

    for part in resolved.parts:
        if part.strip().lower() in _SYNC_CLIENT_MARKERS:
            return part

    # Walk upward looking for sentinel files, which survive a folder rename.
    for ancestor in [resolved, *resolved.parents]:
        for sentinel in _SYNC_CLIENT_SENTINELS:
            if (ancestor / sentinel).exists():
                return f"{ancestor}/{sentinel}"
    return None


@dataclass(frozen=True)
class Settings:
    """Resolved deployment settings.

    Frozen because a setting that can change mid-run is a control that can
    be turned off mid-run.
    """

    #: Root under which all four zones live.
    working_root: Path

    #: Encryption at rest (master prompt §1.1). Disabling it is only
    #: possible in an explicitly-marked non-PHI development sandbox.
    encryption_enabled: bool = True

    #: Set when the operator asserts this instance never touches real PHI.
    #: Gates the synthetic-data-only test posture (master prompt §14).
    development_mode: bool = False

    #: Retention window for Zone B working files (master prompt §5.1).
    working_retention_hours: int = 24

    #: Retention window for raw intake (master prompt §5.1: "do NOT store
    #: full EOB longer than required"). Processing does not consume the
    #: source — a bulk EOB stays in Incoming/ after its patients are
    #: exported — so without this window raw multi-patient PHI accumulates
    #: there indefinitely, which is the largest PHI store in the system.
    #:
    #: The trade-off is real: a document not processed within the window
    #: is deleted unprocessed. The default is generous enough to cover a
    #: long weekend, and the alternative — keeping raw PHI forever — is
    #: not a defensible default for a HIPAA-capable system.
    incoming_retention_hours: int = 72

    #: Quarantine expiry (master prompt §5.1).
    quarantine_retention_days: int = 30

    #: Bind address for any local API. Loopback unless explicitly widened.
    api_host: str = "127.0.0.1"
    api_port: int = 8765

    #: Passphrase env var name for the non-Windows / dev key provider.
    #: The passphrase itself is never stored in settings.
    passphrase_env_var: str = "SECONDARYEOB_PASSPHRASE"

    #: Zone directory names, resolved to absolute paths at construction.
    zone_paths: dict[str, Path] = field(default_factory=dict)

    def path_for(self, directory: str) -> Path:
        """Return the absolute path of a zone directory (e.g. ``"Incoming"``)."""
        if directory not in ZONE_DIRECTORIES:
            raise ConfigError(f"unknown zone directory {directory!r}")
        return self.zone_paths[directory]

    def ensure_directories(self) -> None:
        """Create the zone directories if absent."""
        for path in self.zone_paths.values():
            path.mkdir(parents=True, exist_ok=True)


def load_settings(working_root: Path | str | None = None) -> Settings:
    """Load settings from the environment, refusing unsafe configurations.

    Raises:
        UnsafeWorkingDirectoryError: the root is inside a file-sync folder.
        ConfigError: encryption disabled without a development-mode
            acknowledgement, or a non-loopback API bind without one.
    """
    root_raw = working_root or os.environ.get("SECONDARYEOB_ROOT")
    if not root_raw:
        raise ConfigError(
            "SECONDARYEOB_ROOT is not set. Refusing to guess a location for PHI."
        )
    root = Path(root_raw).expanduser()

    offending = _looks_like_sync_folder(root)
    if offending is not None:
        raise UnsafeWorkingDirectoryError(
            f"working root is inside a file-sync folder ({offending!r}). "
            "A sync client copies PHI off this machine outside every control "
            "this application enforces. Move the working root to local "
            "non-synced storage."
        )

    development_mode = _env_flag("SECONDARYEOB_DEV_MODE", False)
    encryption_enabled = _env_flag("SECONDARYEOB_ENCRYPTION", True)

    if not encryption_enabled and not development_mode:
        raise ConfigError(
            "encryption at rest cannot be disabled outside development mode. "
            "Set SECONDARYEOB_DEV_MODE=1 only on an instance that will never "
            "touch real PHI."
        )

    api_host = os.environ.get("SECONDARYEOB_API_HOST", "127.0.0.1")
    if api_host not in {"127.0.0.1", "localhost", "::1"} and not _env_flag(
        "SECONDARYEOB_ALLOW_PUBLIC_BIND"
    ):
        raise ConfigError(
            f"refusing to bind {api_host}: a non-loopback bind requires TLS 1.2+, "
            "HTTPS only, and token authentication (master prompt §1.2), none of "
            "which the MVP implements. Set SECONDARYEOB_ALLOW_PUBLIC_BIND=1 only "
            "once those exist."
        )

    zone_paths = {name: root / name for name in ZONE_DIRECTORIES}

    return Settings(
        working_root=root,
        encryption_enabled=encryption_enabled,
        development_mode=development_mode,
        working_retention_hours=_env_int("SECONDARYEOB_WORKING_RETENTION_HOURS", 24),
        incoming_retention_hours=_env_int("SECONDARYEOB_INCOMING_RETENTION_HOURS", 72),
        quarantine_retention_days=_env_int("SECONDARYEOB_QUARANTINE_RETENTION_DAYS", 30),
        api_host=api_host,
        api_port=_env_int("SECONDARYEOB_API_PORT", 8765),
        zone_paths=zone_paths,
    )
