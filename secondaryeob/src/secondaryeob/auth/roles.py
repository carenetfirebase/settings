"""Roles and the permissions each one carries (master prompt §2.2).

The permission matrix is a flat constant so that a reviewer can audit
"who can export?" by reading it, rather than by tracing conditionals.

Least privilege drives the assignments:

ADMIN
    Configures the system and can read the audit log, but is deliberately
    *not* granted redaction or export. Separating the person who
    administers the system from the person who releases patient documents
    means a compromised admin account cannot quietly ship PHI out of the
    system on its own.

BILLER
    The production path: intake through export, because that is the job.

REVIEWER
    Read-only over sanitized output and the review queue. Can approve a
    document for export but cannot perform the export, so approval and
    release stay two distinct acts by two distinct roles.
"""

from __future__ import annotations

import enum

from ..zones import Zone


class Role(enum.Enum):
    ADMIN = "ADMIN"
    BILLER = "BILLER"
    REVIEWER = "REVIEWER"


class Permission(enum.Enum):
    """A discrete capability. Checked programmatically, never UI-only."""

    #: Read raw, un-redacted PHI (Zone A). The highest-risk permission.
    READ_RAW_PHI = "READ_RAW_PHI"
    #: Bring a new document into the system.
    INTAKE = "INTAKE"
    #: Run extraction/classification/parsing over Zone A/B data.
    PROCESS = "PROCESS"
    #: Apply redaction.
    REDACT = "REDACT"
    #: Read sanitized output (Zone C).
    READ_SANITIZED = "READ_SANITIZED"
    #: Approve a validated document as fit for release.
    APPROVE = "APPROVE"
    #: Release a document out of the system (to Ready/, then PAD/PMS).
    EXPORT = "EXPORT"
    #: Read the audit log.
    READ_AUDIT = "READ_AUDIT"
    #: Delete PHI / run retention purges.
    PURGE = "PURGE"
    #: Change configuration.
    ADMINISTER = "ADMINISTER"


_ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.ADMIN: frozenset(
        {
            Permission.ADMINISTER,
            Permission.READ_AUDIT,
            Permission.PURGE,
            Permission.READ_SANITIZED,
        }
    ),
    Role.BILLER: frozenset(
        {
            Permission.INTAKE,
            Permission.READ_RAW_PHI,
            Permission.PROCESS,
            Permission.REDACT,
            Permission.READ_SANITIZED,
            Permission.EXPORT,
        }
    ),
    Role.REVIEWER: frozenset(
        {
            Permission.READ_SANITIZED,
            Permission.APPROVE,
            Permission.READ_AUDIT,
        }
    ),
}


def permissions_for(role: Role) -> frozenset[Permission]:
    """Return the permissions carried by ``role``."""
    return _ROLE_PERMISSIONS[role]


#: The permission required to read each zone. Enforced by the guard on
#: every file access, so there is no path to a Zone A byte without
#: READ_RAW_PHI.
ZONE_READ_PERMISSION: dict[Zone, Permission] = {
    Zone.A_RAW_PHI: Permission.READ_RAW_PHI,
    Zone.B_PROCESSING: Permission.PROCESS,
    Zone.C_SANITIZED: Permission.READ_SANITIZED,
    Zone.D_LOGS: Permission.READ_AUDIT,
}

#: The permission required to write into each zone.
#:
#: Zone D is ADMINISTER because no *user* should be writing log files
#: directly. Audit appends are a system action performed on behalf of the
#: principal and deliberately do not route through the guard — an
#: ACCESS_DENIED entry has to be recorded for a principal who by
#: definition holds no permissions, so gating the audit write on a
#: permission would mean the denials that matter most never get logged.
ZONE_WRITE_PERMISSION: dict[Zone, Permission] = {
    Zone.A_RAW_PHI: Permission.INTAKE,
    Zone.B_PROCESSING: Permission.PROCESS,
    Zone.C_SANITIZED: Permission.REDACT,
    Zone.D_LOGS: Permission.ADMINISTER,
}
