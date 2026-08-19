"""The authorization guard — enforced on every file access (master prompt §2.2).

The guard is the *only* sanctioned route to a PHI-bearing file. Pipeline
stages call :meth:`Guard.read` / :meth:`Guard.write` rather than touching
the vault or the filesystem directly, so a denial happens before any byte
is read rather than after a UI decided not to show it.

Every check produces an audit entry — grants as well as denials. A log
that only records failures cannot answer "who read this patient's file",
which is the question an audit is for.

Path containment is checked before the permission check: a path that
resolves outside the working root has no zone, and a request for it is
refused rather than defaulted to the most permissive zone.
"""

from __future__ import annotations

from pathlib import Path

from ..audit import Action, AuditLog, Outcome
from ..audit.log import content_ref
from ..crypto import Vault
from ..errors import AuthorizationError
from ..zones import Zone, policy_for, zone_of
from .identity import Principal
from .roles import ZONE_READ_PERMISSION, ZONE_WRITE_PERMISSION, Permission


class Guard:
    """Mediates every access to a zone-resident file."""

    def __init__(
        self,
        principal: Principal,
        vault: Vault,
        audit: AuditLog,
        working_root: Path,
        *,
        job_id: str = "-",
    ) -> None:
        self._principal = principal
        self._vault = vault
        self._audit = audit
        self._root = working_root
        self._job_id = job_id

    @property
    def principal(self) -> Principal:
        return self._principal

    def for_job(self, job_id: str) -> Guard:
        """Return a guard bound to ``job_id`` for audit correlation."""
        return Guard(
            self._principal, self._vault, self._audit, self._root, job_id=job_id
        )

    # --- checks --------------------------------------------------------

    def _audit_decision(
        self,
        *,
        granted: bool,
        permission: Permission,
        zone: Zone | None,
        target_ref: str,
        operation: str,
    ) -> None:
        self._audit.append(
            actor=self._principal.username,
            role=self._principal.role.value,
            job_id=self._job_id,
            action=Action.ACCESS_GRANTED if granted else Action.ACCESS_DENIED,
            zone=zone.value if zone else "-",
            target_ref=target_ref,
            outcome=Outcome.SUCCESS if granted else Outcome.BLOCKED,
            detail={"permission": permission.value, "operation": operation},
        )

    def require(self, permission: Permission, *, target_ref: str = "-") -> None:
        """Require a bare permission, unrelated to a specific file."""
        granted = self._principal.has(permission)
        self._audit_decision(
            granted=granted,
            permission=permission,
            zone=None,
            target_ref=target_ref,
            operation="require",
        )
        if not granted:
            raise AuthorizationError(
                f"role {self._principal.role.value} lacks {permission.value}"
            )

    def _resolve_zone(self, path: Path, operation: str) -> Zone:
        zone = zone_of(path, self._root)
        if zone is None:
            # No zone means no policy, and no policy means no basis on
            # which to allow the access.
            self._audit.append(
                actor=self._principal.username,
                role=self._principal.role.value,
                job_id=self._job_id,
                action=Action.ACCESS_DENIED,
                zone="-",
                target_ref="-",
                outcome=Outcome.BLOCKED,
                detail={"operation": operation, "reason": "path_outside_working_root"},
            )
            raise AuthorizationError(
                "refusing access to a path outside the working root, or in a "
                "directory that maps to no zone"
            )
        return zone

    def _check_zone(self, path: Path, permission_map: dict[Zone, Permission], operation: str) -> Zone:
        zone = self._resolve_zone(path, operation)
        permission = permission_map[zone]
        granted = self._principal.has(permission)
        self._audit_decision(
            granted=granted,
            permission=permission,
            zone=zone,
            target_ref=path.name,
            operation=operation,
        )
        if not granted:
            raise AuthorizationError(
                f"role {self._principal.role.value} lacks {permission.value} "
                f"required to {operation} in {zone} (risk {policy_for(zone).risk})"
            )
        return zone

    # --- mediated file access -----------------------------------------

    def read(self, path: Path) -> bytes:
        """Authorize, then decrypt and return the contents of ``path``."""
        zone = self._check_zone(path, ZONE_READ_PERMISSION, "read")
        return self._vault.read(path, zone=zone)

    def write(self, path: Path, plaintext: bytes) -> None:
        """Authorize, then encrypt ``plaintext`` to ``path``."""
        zone = self._check_zone(path, ZONE_WRITE_PERMISSION, "write")
        self._vault.write(path, plaintext, zone=zone)

    def delete(self, path: Path) -> None:
        """Authorize and delete ``path``, recording the deletion."""
        self.require(Permission.PURGE, target_ref=path.name)
        zone = self._resolve_zone(path, "delete")
        path.unlink(missing_ok=True)
        self._audit.append(
            actor=self._principal.username,
            role=self._principal.role.value,
            job_id=self._job_id,
            action=Action.DELETE,
            zone=zone.value,
            target_ref=path.name,
            outcome=Outcome.SUCCESS,
            detail={"still_present": path.exists()},
        )

    def record(
        self,
        action: Action,
        *,
        outcome: Outcome,
        zone: Zone | None = None,
        target_ref: str = "-",
        detail: dict | None = None,
    ) -> None:
        """Record a pipeline action against this guard's principal and job."""
        self._audit.append(
            actor=self._principal.username,
            role=self._principal.role.value,
            job_id=self._job_id,
            action=action,
            zone=zone.value if zone else "-",
            target_ref=target_ref,
            outcome=outcome,
            detail=detail or {},
        )


__all__ = ["Guard", "content_ref"]
