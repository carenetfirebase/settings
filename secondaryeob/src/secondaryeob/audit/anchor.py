"""Audit chain anchoring — detecting truncation and rewritten history.

A hash chain proves that entry *N* follows entry *N-1*. It proves nothing
about how many entries there should be, so it cannot detect the simplest
useful attack: **deleting entries off the end**. Remove the last five
records — an export, a denial, a suspected breach — and the remaining
chain verifies perfectly, because a shorter valid chain is still a valid
chain.

An anchor is a periodic, externally-recorded note of "at time T the log
held N entries and its head hash was H". With anchors:

* **Truncation** is caught: the log now holds fewer entries than an anchor
  says it did.
* **Rewritten history** is caught: the log holds enough entries, but the
  entry at the anchored position no longer hashes to the anchored value.

Anchors are themselves chained, so the anchor file cannot be quietly
pruned either.

**How much this is worth depends entirely on where the anchors live.**
Kept in the default location next to the audit log, anchoring raises the
bar — an attacker must now find and consistently rewrite two files instead
of one — but a sufficiently careful attacker with write access to both can
still forge a consistent story. It is defence in depth, not a proof.

Anchoring becomes genuinely strong when the anchor record reaches somewhere
the attacker cannot write:

* a WORM volume or write-protected share (set ``anchor_path``),
* a remote log service or ticket system,
* a printed or emailed head hash filed with the compliance record.

:func:`AnchorStore.latest` returns the value to record externally, and
:meth:`AnchorStore.verify_head` checks a hash recovered from such an
external record against the live log. That last path is the one that
survives a fully-compromised machine, which is why the CLI surfaces the
head hash for the operator to file rather than only writing it to disk.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from ..errors import AuditIntegrityError
from .log import GENESIS_HASH, AuditLog

_ANCHOR_GENESIS = "0" * 64


@dataclass(frozen=True)
class Anchor:
    """A recorded observation of the audit log's length and head hash."""

    index: int
    timestamp: str
    entry_count: int
    head_hash: str
    prev_anchor_hash: str
    anchor_hash: str = ""

    def payload(self) -> dict:
        return {
            "index": self.index,
            "timestamp": self.timestamp,
            "entry_count": self.entry_count,
            "head_hash": self.head_hash,
            "prev_anchor_hash": self.prev_anchor_hash,
        }

    def compute_hash(self) -> str:
        canonical = json.dumps(
            self.payload(), sort_keys=True, separators=(",", ":"), ensure_ascii=True
        )
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def to_json(self) -> str:
        record = self.payload()
        record["anchor_hash"] = self.anchor_hash
        return json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=True)

    @classmethod
    def from_json(cls, line: str) -> Anchor:
        raw = json.loads(line)
        return cls(
            index=raw["index"],
            timestamp=raw["timestamp"],
            entry_count=raw["entry_count"],
            head_hash=raw["head_hash"],
            prev_anchor_hash=raw["prev_anchor_hash"],
            anchor_hash=raw["anchor_hash"],
        )


class AnchorStore:
    """An append-only, chained record of audit log observations."""

    def __init__(self, path: Path) -> None:
        self._path = path

    @property
    def path(self) -> Path:
        return self._path

    def read_all(self) -> list[Anchor]:
        """Return every anchor, verifying the anchor chain itself."""
        if not self._path.exists():
            return []

        anchors: list[Anchor] = []
        expected_prev = _ANCHOR_GENESIS
        expected_index = 0

        with self._path.open("r", encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    anchor = Anchor.from_json(line)
                except (json.JSONDecodeError, KeyError) as exc:
                    raise AuditIntegrityError(
                        f"anchor file line {lineno} is malformed: {exc}"
                    ) from exc

                if anchor.index != expected_index:
                    raise AuditIntegrityError(
                        f"anchor sequence gap: expected {expected_index}, "
                        f"found {anchor.index}. Anchors have been removed."
                    )
                if anchor.prev_anchor_hash != expected_prev:
                    raise AuditIntegrityError(
                        f"anchor chain broken at anchor {anchor.index}"
                    )
                if anchor.compute_hash() != anchor.anchor_hash:
                    raise AuditIntegrityError(
                        f"anchor {anchor.index} has been modified"
                    )

                anchors.append(anchor)
                expected_prev = anchor.anchor_hash
                expected_index += 1

        return anchors

    def latest(self) -> Anchor | None:
        """Return the most recent anchor, or ``None`` if there are none."""
        anchors = self.read_all()
        return anchors[-1] if anchors else None

    def record(self, log: AuditLog) -> Anchor:
        """Append an anchor for ``log``'s current state."""
        existing = self.read_all()
        anchor = Anchor(
            index=len(existing),
            timestamp=datetime.now(timezone.utc).isoformat(timespec="microseconds"),
            entry_count=log.entry_count,
            head_hash=log.head_hash,
            prev_anchor_hash=existing[-1].anchor_hash if existing else _ANCHOR_GENESIS,
        )
        anchor = Anchor(**{**anchor.payload(), "anchor_hash": anchor.compute_hash()})

        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._path.open("a", encoding="utf-8") as handle:
            handle.write(anchor.to_json() + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        try:
            self._path.chmod(0o600)
        except OSError:  # pragma: no cover - platform dependent
            pass
        return anchor

    def verify(self, log: AuditLog) -> None:
        """Check the live log against every recorded anchor.

        Raises:
            AuditIntegrityError: the log is shorter than an anchor recorded
                (entries deleted from the end), or the anchored position no
                longer hashes to the anchored value (history rewritten).
        """
        anchors = self.read_all()
        if not anchors:
            return

        entries = log.read_entries_list()

        for anchor in anchors:
            if len(entries) < anchor.entry_count:
                raise AuditIntegrityError(
                    f"AUDIT LOG TRUNCATED: anchor {anchor.index} recorded "
                    f"{anchor.entry_count} entries at {anchor.timestamp}, but the "
                    f"log now holds only {len(entries)}. "
                    f"{anchor.entry_count - len(entries)} entries have been deleted "
                    "from the end — which the hash chain alone cannot detect."
                )
            if anchor.entry_count == 0:
                continue
            anchored_entry = entries[anchor.entry_count - 1]
            if anchored_entry.entry_hash != anchor.head_hash:
                raise AuditIntegrityError(
                    f"AUDIT HISTORY REWRITTEN: anchor {anchor.index} recorded head "
                    f"hash {anchor.head_hash[:16]}... at entry {anchor.entry_count}, "
                    f"but that position now hashes to "
                    f"{anchored_entry.entry_hash[:16]}.... The log has been rebuilt "
                    "since the anchor was taken."
                )

    def verify_head(self, log: AuditLog, external_head_hash: str, entry_count: int) -> None:
        """Verify the log against a head hash recovered from outside the machine.

        This is the check that survives an attacker who controls both the
        log and the anchor file: the operator supplies a head hash filed
        externally (printed, emailed, held in a ticket), and it either
        matches the log or it does not.
        """
        entries = log.read_entries_list()
        if len(entries) < entry_count:
            raise AuditIntegrityError(
                f"AUDIT LOG TRUNCATED: externally recorded state had {entry_count} "
                f"entries, the log now holds {len(entries)}."
            )
        if entry_count == 0:
            return
        actual = entries[entry_count - 1].entry_hash
        if actual != external_head_hash:
            raise AuditIntegrityError(
                f"AUDIT HISTORY REWRITTEN: externally recorded head hash "
                f"{external_head_hash[:16]}... does not match the log's "
                f"{actual[:16]}... at entry {entry_count}."
            )


__all__ = ["Anchor", "AnchorStore", "GENESIS_HASH"]
