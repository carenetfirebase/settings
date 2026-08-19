"""Security boundary model — the four data zones (master prompt §9).

The zone a byte lives in determines what may touch it. This module is the
single definition of that model; the guard (``auth.guard``), the vault
(``crypto.vault``), and every pipeline stage import from here rather than
carrying their own idea of what counts as raw PHI.

    Zone A — Raw PHI (HIGH RISK): incoming PDFs, OCR output, extracted text
    Zone B — Processing: deterministic parsing, temporary structures
    Zone C — Sanitized output: redacted PDFs, approved attachments
    Zone D — Logs: audit and system logs, PHI-free where possible

The LLM may only ever see Zone B, and only an anonymized subset of it.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass
from pathlib import Path


class Zone(enum.Enum):
    """A data zone in the security boundary model."""

    A_RAW_PHI = "A"
    B_PROCESSING = "B"
    C_SANITIZED = "C"
    D_LOGS = "D"

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"Zone{self.value}"


@dataclass(frozen=True)
class ZonePolicy:
    """What the system is permitted to do with data in a zone."""

    zone: Zone
    #: Human-readable risk tier, used in audit entries and error text.
    risk: str
    #: Encryption at rest is mandatory (master prompt §1.1).
    requires_encryption: bool
    #: May be exposed to the local LLM, in anonymized form only (§9).
    llm_accessible: bool
    #: May leave the application boundary (e.g. read by Power Automate
    #: Desktop, or attached into a PMS). Only sanitized output may.
    externally_readable: bool


#: The policy table. This is deliberately a flat, readable constant rather
#: than logic — a reviewer auditing the LLM boundary or the PAD boundary
#: should be able to confirm it by reading four rows.
ZONE_POLICIES: dict[Zone, ZonePolicy] = {
    Zone.A_RAW_PHI: ZonePolicy(
        zone=Zone.A_RAW_PHI,
        risk="HIGH",
        requires_encryption=True,
        llm_accessible=False,
        externally_readable=False,
    ),
    Zone.B_PROCESSING: ZonePolicy(
        zone=Zone.B_PROCESSING,
        risk="HIGH",
        requires_encryption=True,
        # Anonymized subset only — see llm.boundary for the transform that
        # must run before anything from Zone B reaches a model.
        llm_accessible=True,
        externally_readable=False,
    ),
    Zone.C_SANITIZED: ZonePolicy(
        zone=Zone.C_SANITIZED,
        risk="CONTROLLED",
        # Still encrypted: a sanitized EOB is still a patient's record,
        # it just no longer carries *other* patients' PHI.
        requires_encryption=True,
        llm_accessible=False,
        externally_readable=True,
    ),
    Zone.D_LOGS: ZonePolicy(
        zone=Zone.D_LOGS,
        risk="METADATA",
        # PHI-free by construction, but job/file correlation is still
        # sensitive metadata, so it is encrypted anyway.
        requires_encryption=True,
        llm_accessible=False,
        externally_readable=False,
    ),
}


def policy_for(zone: Zone) -> ZonePolicy:
    """Return the policy governing ``zone``."""
    return ZONE_POLICIES[zone]


#: Directory name under the working root for each zone. ``Incoming`` and
#: ``Quarantine`` are both Zone A: a quarantined document is a document
#: whose PHI is *more* uncertain, not less.
ZONE_DIRECTORIES: dict[str, Zone] = {
    "Incoming": Zone.A_RAW_PHI,
    "Quarantine": Zone.A_RAW_PHI,
    "Working": Zone.B_PROCESSING,
    "Ready": Zone.C_SANITIZED,
    "Logs": Zone.D_LOGS,
}


def zone_of(path: Path, root: Path) -> Zone | None:
    """Return the zone ``path`` belongs to, or ``None`` if outside the root.

    Resolves both paths first so that a symlink or ``..`` segment cannot
    present a Zone A file as though it were in Zone C.
    """
    try:
        resolved = path.resolve()
        relative = resolved.relative_to(root.resolve())
    except (ValueError, OSError):
        return None

    if not relative.parts:
        return None
    return ZONE_DIRECTORIES.get(relative.parts[0])
