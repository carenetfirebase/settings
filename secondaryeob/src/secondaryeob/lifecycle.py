"""PHI lifecycle management (master prompt §5).

Retention is enforced by deleting, and deletion is enforced by checking
that the file is gone. ``unlink`` that silently fails, or a file a handle
still holds open, leaves PHI on disk while the system believes it is gone
— which is worse than not having a retention policy, because it is a
retention policy that reports success.

On the limits of "unrecoverable": this deletes the directory entry, and
because every PHI file is written encrypted, the residual blocks on disk
are ciphertext. That is the real protection — the plaintext was never on
the platter to begin with. Overwriting before unlink is deliberately not
attempted: on an SSD with wear levelling, or on a copy-on-write
filesystem, overwriting a file's logical blocks does not overwrite the
physical ones, so it would provide a false assurance rather than a real
one. Media sanitisation at end of life remains an operational control
(NIST SP 800-88), not something this code can perform.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .audit import Action, Outcome
from .auth.guard import Guard
from .auth.roles import Permission
from .config import Settings
from .errors import DeletionVerificationError
from .zones import Zone


@dataclass
class PurgeReport:
    """What a retention run removed."""

    scanned: int = 0
    deleted: int = 0
    failed: int = 0

    @property
    def clean(self) -> bool:
        return self.failed == 0


def verified_delete(path: Path) -> None:
    """Delete ``path`` and confirm it is gone.

    Raises:
        DeletionVerificationError: the file still exists afterwards.
    """
    try:
        path.unlink(missing_ok=True)
    except OSError as exc:
        raise DeletionVerificationError(
            f"could not delete {path.name}: {type(exc).__name__}"
        ) from exc

    if path.exists():
        raise DeletionVerificationError(
            f"{path.name} still exists after deletion. It may be held open by "
            "another process. PHI is still on disk; treat this as unresolved."
        )


def _expired(path: Path, cutoff: datetime) -> bool:
    try:
        modified = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:  # pragma: no cover - race with another deleter
        return False
    return modified < cutoff


def purge_expired(guard: Guard, settings: Settings) -> PurgeReport:
    """Delete Zone B working files and expired quarantine items.

    Requires :attr:`Permission.PURGE`. Every deletion is audited
    individually — a retention run that logged only a total would not let
    anyone confirm afterwards that a specific record was destroyed.
    """
    guard.require(Permission.PURGE)
    report = PurgeReport()
    now = datetime.now(timezone.utc)

    targets: list[tuple[Path, datetime, Zone]] = [
        (
            # Processing does not consume the source document, so without
            # this Incoming/ becomes an ever-growing store of raw
            # multi-patient PHI — the opposite of minimum necessary.
            settings.path_for("Incoming"),
            now - timedelta(hours=settings.incoming_retention_hours),
            Zone.A_RAW_PHI,
        ),
        (
            settings.path_for("Working"),
            now - timedelta(hours=settings.working_retention_hours),
            Zone.B_PROCESSING,
        ),
        (
            settings.path_for("Quarantine"),
            now - timedelta(days=settings.quarantine_retention_days),
            Zone.A_RAW_PHI,
        ),
    ]

    for directory, cutoff, zone in targets:
        if not directory.exists():
            continue
        for path in sorted(directory.iterdir()):
            if not path.is_file():
                continue
            report.scanned += 1
            if not _expired(path, cutoff):
                continue
            try:
                verified_delete(path)
                report.deleted += 1
                guard.record(
                    Action.DELETE,
                    outcome=Outcome.SUCCESS,
                    zone=zone,
                    target_ref=path.name,
                    detail={"reason": "retention_expiry"},
                )
            except DeletionVerificationError:
                report.failed += 1
                guard.record(
                    Action.DELETE,
                    outcome=Outcome.FAILURE,
                    zone=zone,
                    target_ref=path.name,
                    detail={"reason": "deletion_unverified"},
                )

    return report
