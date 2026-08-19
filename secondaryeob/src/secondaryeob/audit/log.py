"""Append-only, tamper-evident audit log.

Each entry commits to the hash of the entry before it, so altering or
removing any historical entry breaks the chain from that point forward and
:meth:`AuditLog.verify_chain` detects it. This is *tamper-evident*, not
tamper-proof: an attacker with write access can rewrite the whole file and
recompute every hash. Genuine tamper-resistance needs the chain anchored
somewhere the attacker does not control — WORM storage, or periodically
publishing the head hash off-box. That anchoring is deferred with the rest
of the backup/DR work (plan §E) and is a go-live blocker.

Plan §F names the failure mode that makes a chain useless: nobody checks
it. So verification is not a maintenance command — :meth:`AuditLog.open`
verifies before it will hand back a writable log, and refuses to append to
a chain that does not verify.

PHI-free by construction (master prompt §14): entries reference documents
by job ID and content hash, never by patient name or filename. The
``detail`` payload runs through a key/-value screen that rejects the
obvious PHI carriers. That screen is a backstop against mistakes, not a
guarantee — it cannot tell that ``{"note": "Jane Doe"}`` carries a name.
The real control is that callers pass identifiers, and review enforces it.
"""

from __future__ import annotations

import enum
import hashlib
import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from ..errors import AuditIntegrityError, PHIInAuditError

#: Hash of the notional entry before the first one.
GENESIS_HASH = "0" * 64


class Action(enum.Enum):
    """Auditable actions. Every PHI touch is one of these."""

    INTAKE = "INTAKE"
    EXTRACT = "EXTRACT"
    CLASSIFY = "CLASSIFY"
    PARSE = "PARSE"
    REDACT = "REDACT"
    VALIDATE = "VALIDATE"
    EXPORT = "EXPORT"
    QUARANTINE = "QUARANTINE"
    DELETE = "DELETE"
    ACCESS_GRANTED = "ACCESS_GRANTED"
    ACCESS_DENIED = "ACCESS_DENIED"
    AUTH = "AUTH"
    LLM_CALL = "LLM_CALL"
    BREACH_SUSPECTED = "BREACH_SUSPECTED"
    SYSTEM = "SYSTEM"


class Outcome(enum.Enum):
    SUCCESS = "SUCCESS"
    FAILURE = "FAILURE"
    BLOCKED = "BLOCKED"
    REVIEW_REQUIRED = "REVIEW_REQUIRED"


#: Keys that must never appear in an audit detail payload.
_FORBIDDEN_DETAIL_KEYS = frozenset(
    {
        "name", "patient", "patient_name", "first_name", "last_name", "surname",
        "dob", "date_of_birth", "birthdate", "ssn", "sin", "member_id", "memberid",
        "subscriber_id", "policy_number", "address", "phone", "email", "text",
        "content", "raw", "extracted_text", "page_text", "prompt", "filename",
        "file_name", "original_name",
    }
)

#: Detail values are identifiers and counts, so anything long is suspect.
_MAX_DETAIL_VALUE_LEN = 128

_SSN_RE = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
_DOB_RE = re.compile(r"\b\d{1,2}[/-]\d{1,2}[/-](?:19|20)\d{2}\b")


def _assert_phi_free(detail: dict[str, Any]) -> None:
    """Reject detail payloads that obviously carry PHI.

    A backstop, not a guarantee — see the module docstring.
    """
    for key, value in detail.items():
        if key.lower() in _FORBIDDEN_DETAIL_KEYS:
            raise PHIInAuditError(
                f"audit detail key {key!r} is a PHI carrier; log an identifier "
                "or a content hash instead"
            )
        if isinstance(value, str):
            if len(value) > _MAX_DETAIL_VALUE_LEN:
                raise PHIInAuditError(
                    f"audit detail {key!r} is {len(value)} chars; audit values are "
                    "identifiers and counts, so this looks like document content"
                )
            if _SSN_RE.search(value) or _DOB_RE.search(value):
                raise PHIInAuditError(
                    f"audit detail {key!r} matches an SSN/DOB pattern"
                )
        elif not isinstance(value, (int, float, bool, type(None))):
            raise PHIInAuditError(
                f"audit detail {key!r} must be a primitive, got {type(value).__name__}"
            )


@dataclass(frozen=True)
class AuditEntry:
    """One immutable audit record."""

    seq: int
    timestamp: str
    actor: str
    role: str
    job_id: str
    action: str
    zone: str
    target_ref: str
    outcome: str
    detail: dict[str, Any] = field(default_factory=dict)
    prev_hash: str = GENESIS_HASH
    entry_hash: str = ""

    def payload(self) -> dict[str, Any]:
        """The hashed portion of the entry — everything but its own hash."""
        return {
            "seq": self.seq,
            "timestamp": self.timestamp,
            "actor": self.actor,
            "role": self.role,
            "job_id": self.job_id,
            "action": self.action,
            "zone": self.zone,
            "target_ref": self.target_ref,
            "outcome": self.outcome,
            "detail": self.detail,
            "prev_hash": self.prev_hash,
        }

    def compute_hash(self) -> str:
        """Hash the canonical serialization of this entry's payload."""
        canonical = json.dumps(
            self.payload(), sort_keys=True, separators=(",", ":"), ensure_ascii=True
        )
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def to_json(self) -> str:
        record = self.payload()
        record["entry_hash"] = self.entry_hash
        return json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=True)

    @classmethod
    def from_json(cls, line: str) -> AuditEntry:
        raw = json.loads(line)
        return cls(
            seq=raw["seq"],
            timestamp=raw["timestamp"],
            actor=raw["actor"],
            role=raw["role"],
            job_id=raw["job_id"],
            action=raw["action"],
            zone=raw["zone"],
            target_ref=raw["target_ref"],
            outcome=raw["outcome"],
            detail=raw.get("detail", {}),
            prev_hash=raw["prev_hash"],
            entry_hash=raw["entry_hash"],
        )


class AuditLog:
    """A write-once JSONL log whose entries form a hash chain.

    The log is stored unencrypted so that chain verification does not
    depend on key availability — a log you cannot read during an incident
    because the DEK is gone is not an audit control. It is kept PHI-free
    by construction so that this is a safe trade; see the module
    docstring.
    """

    def __init__(self, path: Path) -> None:
        self._path = path
        self._head_hash = GENESIS_HASH
        self._next_seq = 0
        self._opened = False

    @property
    def path(self) -> Path:
        return self._path

    @property
    def head_hash(self) -> str:
        return self._head_hash

    @property
    def entry_count(self) -> int:
        return self._next_seq

    @classmethod
    def open(cls, path: Path) -> AuditLog:
        """Open (creating if needed) and verify the chain before allowing writes.

        Raises:
            AuditIntegrityError: the existing chain does not verify.
        """
        log = cls(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            entries = log.verify_chain()
            if entries:
                log._head_hash = entries[-1].entry_hash
                log._next_seq = entries[-1].seq + 1
        else:
            path.touch()
            try:
                path.chmod(0o600)
            except OSError:  # pragma: no cover - platform dependent
                pass
        log._opened = True
        return log

    def read_entries(self) -> Iterator[AuditEntry]:
        """Yield every entry in file order."""
        if not self._path.exists():
            return
        with self._path.open("r", encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    yield AuditEntry.from_json(line)
                except (json.JSONDecodeError, KeyError) as exc:
                    raise AuditIntegrityError(
                        f"audit log line {lineno} is malformed: {exc}"
                    ) from exc

    def verify_chain(self) -> list[AuditEntry]:
        """Recompute every hash and confirm the chain is intact.

        Returns:
            The verified entries, oldest first.

        Raises:
            AuditIntegrityError: a hash mismatch, a broken link, or a
                sequence gap — any of which means the record has been
                altered since it was written.
        """
        entries: list[AuditEntry] = []
        expected_prev = GENESIS_HASH
        expected_seq = 0

        for entry in self.read_entries():
            if entry.seq != expected_seq:
                raise AuditIntegrityError(
                    f"audit sequence gap: expected {expected_seq}, found {entry.seq}. "
                    "Entries have been removed or reordered."
                )
            if entry.prev_hash != expected_prev:
                raise AuditIntegrityError(
                    f"audit chain broken at entry {entry.seq}: prev_hash does not "
                    "match the preceding entry's hash."
                )
            recomputed = entry.compute_hash()
            if recomputed != entry.entry_hash:
                raise AuditIntegrityError(
                    f"audit entry {entry.seq} has been modified: recorded hash "
                    "does not match its contents."
                )
            entries.append(entry)
            expected_prev = entry.entry_hash
            expected_seq += 1

        return entries

    def append(
        self,
        *,
        actor: str,
        role: str,
        job_id: str,
        action: Action,
        zone: str,
        target_ref: str,
        outcome: Outcome,
        detail: dict[str, Any] | None = None,
    ) -> AuditEntry:
        """Append one entry, chaining it to the current head.

        Args:
            target_ref: An identifier or content hash. Never a filename or
                a patient name — see the module docstring.

        Raises:
            PHIInAuditError: the detail payload looked like it carried PHI.
            AuditError: the entry could not be durably written.
        """
        if not self._opened:
            raise AuditIntegrityError("audit log must be opened (and verified) before use")

        detail = dict(detail or {})
        _assert_phi_free(detail)

        entry = AuditEntry(
            seq=self._next_seq,
            timestamp=datetime.now(timezone.utc).isoformat(timespec="microseconds"),
            actor=actor,
            role=role,
            job_id=job_id,
            action=action.value,
            zone=zone,
            target_ref=target_ref,
            outcome=outcome.value,
            detail=detail,
            prev_hash=self._head_hash,
        )
        entry = AuditEntry(**{**entry.payload(), "entry_hash": entry.compute_hash()})

        # Append-only: opened in "a" mode, and fsynced so the record
        # survives a crash between the action and the log of it.
        with self._path.open("a", encoding="utf-8") as handle:
            handle.write(entry.to_json() + "\n")
            handle.flush()
            os.fsync(handle.fileno())

        self._head_hash = entry.entry_hash
        self._next_seq += 1
        return entry


def content_ref(data: bytes) -> str:
    """Return a short content hash suitable for use as an audit ``target_ref``.

    Lets two entries be correlated to the same document without the log
    ever recording what the document is.
    """
    return hashlib.sha256(data).hexdigest()[:32]
