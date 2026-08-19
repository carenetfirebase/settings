"""The attach manifest — which sanitized file belongs to which patient.

Output filenames are deliberately PHI-free pseudonyms
(``81b23571ecc6-pt-ff12c1db.pdf``), because filenames leak far beyond the
folder they live in: backup indexes, file dialogs, recent-document lists,
search indexers, and any log that records a path. That decision is right,
and on its own it makes the documents unusable — a biller cannot tell
whose chart a file belongs to without opening it, which for a
200-patient bulk EOB is untenable.

The manifest is what replaces the filename. It maps each pseudonym to the
patient it belongs to, along with enough claim detail to file it, and it
lives encrypted in Zone C rather than as readable text on disk. So the
identity is available to an authenticated biller in one command, and
nowhere else.

The same record is what any downstream automation needs — a Power
Automate Desktop flow or a PMS connector has exactly the same question
("which chart does this file go in?") and no other way to answer it. The
manifest is therefore the hinge for the whole last mile, not just a
convenience for humans.

**This file contains PHI.** It is encrypted at rest like every other
PHI-bearing artifact, reached only through the guard, and never written
to logs. Reading it requires ``READ_SANITIZED`` — the same permission
that already allows opening the sanitized PDFs it describes, so it grants
no visibility that Zone C did not already grant.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from .audit import Action, Outcome
from .auth.guard import Guard
from .errors import SecondaryEOBError

MANIFEST_FILENAME = "manifest.jsonl"


@dataclass
class ManifestEntry:
    """One sanitized document and the patient it belongs to.

    PHI-bearing fields are excluded from ``repr`` so an accidental log
    line, traceback, or debugger dump does not print a patient's name.
    """

    #: Non-identifying handle, matching the exported filename.
    pseudonym: str
    #: Filename in Ready/.
    filename: str
    #: Content hash of the source batch, for grouping.
    source_ref: str
    exported_at: str

    #: --- PHI ---
    patient_name: str = field(default="", repr=False)
    date_of_birth: str | None = field(default=None, repr=False)
    member_id: str | None = field(default=None, repr=False)

    #: Claim summary, enough to file the document without opening it.
    procedure_codes: tuple[str, ...] = field(default=(), repr=False)
    patient_responsibility: str | None = field(default=None, repr=False)

    #: Attachment tracking, so a large batch is resumable rather than a
    #: guessing game about where someone left off.
    attached: bool = False
    attached_at: str | None = None
    attached_by: str | None = None

    def to_json(self) -> str:
        return json.dumps(
            {
                "pseudonym": self.pseudonym,
                "filename": self.filename,
                "source_ref": self.source_ref,
                "exported_at": self.exported_at,
                "patient_name": self.patient_name,
                "date_of_birth": self.date_of_birth,
                "member_id": self.member_id,
                "procedure_codes": list(self.procedure_codes),
                "patient_responsibility": self.patient_responsibility,
                "attached": self.attached,
                "attached_at": self.attached_at,
                "attached_by": self.attached_by,
            },
            separators=(",", ":"),
        )

    @classmethod
    def from_json(cls, line: str) -> ManifestEntry:
        raw = json.loads(line)
        return cls(
            pseudonym=raw["pseudonym"],
            filename=raw["filename"],
            source_ref=raw["source_ref"],
            exported_at=raw["exported_at"],
            patient_name=raw.get("patient_name", ""),
            date_of_birth=raw.get("date_of_birth"),
            member_id=raw.get("member_id"),
            procedure_codes=tuple(raw.get("procedure_codes", [])),
            patient_responsibility=raw.get("patient_responsibility"),
            attached=raw.get("attached", False),
            attached_at=raw.get("attached_at"),
            attached_by=raw.get("attached_by"),
        )


class Manifest:
    """The encrypted index of sanitized documents to patients."""

    def __init__(self, path: Path, guard: Guard) -> None:
        self._path = path
        self._guard = guard

    @property
    def path(self) -> Path:
        return self._path

    def read(self) -> list[ManifestEntry]:
        """Return every entry. Requires READ_SANITIZED."""
        if not self._path.exists():
            return []
        raw = self._guard.read(self._path).decode("utf-8")
        entries = []
        for lineno, line in enumerate(raw.splitlines(), start=1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(ManifestEntry.from_json(line))
            except (json.JSONDecodeError, KeyError) as exc:
                raise SecondaryEOBError(
                    f"manifest line {lineno} is malformed: {exc}"
                ) from exc
        return entries

    def _write_all(self, entries: list[ManifestEntry]) -> None:
        payload = "\n".join(entry.to_json() for entry in entries)
        if payload:
            payload += "\n"
        self._guard.write(self._path, payload.encode("utf-8"))

    def append(self, entry: ManifestEntry) -> None:
        """Add an entry, replacing any earlier one for the same pseudonym.

        Reprocessing the same batch overwrites rather than duplicates, so
        the worklist does not accumulate stale rows for documents that
        were re-exported.
        """
        entries = [e for e in self.read() if e.pseudonym != entry.pseudonym]
        entries.append(entry)
        self._write_all(entries)

    def mark_attached(self, pseudonym: str, *, by: str) -> ManifestEntry:
        """Record that a document has been filed into the PMS.

        Raises:
            SecondaryEOBError: no such pseudonym.
        """
        entries = self.read()
        for index, entry in enumerate(entries):
            if entry.pseudonym != pseudonym:
                continue
            entries[index] = ManifestEntry(
                **{
                    **entry.__dict__,
                    "attached": True,
                    "attached_at": datetime.now(timezone.utc).isoformat(
                        timespec="seconds"
                    ),
                    "attached_by": by,
                }
            )
            self._write_all(entries)
            self._guard.record(
                Action.EXPORT,
                outcome=Outcome.SUCCESS,
                target_ref=pseudonym,
                detail={"event": "marked_attached"},
            )
            return entries[index]

        raise SecondaryEOBError(f"no manifest entry for {pseudonym!r}")

    def pending(self) -> list[ManifestEntry]:
        """Entries not yet filed into the PMS."""
        return [entry for entry in self.read() if not entry.attached]


def summarize_claims(claims) -> tuple[tuple[str, ...], str | None]:
    """Reduce parsed claim lines to what a biller needs to file the document.

    Returns the procedure codes and the total patient responsibility. The
    total is summed only from values actually printed on the EOB — if any
    line's patient responsibility could not be parsed, this returns
    ``None`` rather than a total that silently omits it. A number shown
    next to a patient's name will be read as authoritative, so a partial
    sum is worse than no sum.
    """
    codes = tuple(claim.procedure_code for claim in claims if claim.procedure_code)

    values = [claim.patient_responsibility for claim in claims]
    if not values or any(value is None for value in values):
        return codes, None

    total = sum(values, Decimal("0"))
    return codes, f"{total:.2f}"
