"""Command-line interface.

Deliberately small. Every command opens a session first, which is what
enforces the startup controls (sync-folder check, audit chain
verification, key unwrap, role resolution) — so there is no command that
runs against an uncontrolled working root.

Nothing here prints PHI. Patient records are referred to by pseudonym,
which is what the operator sees on screen and in the output filenames.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
from pathlib import Path

from .audit import AuditLog
from .auth.identity import current_subject
from .config import load_settings
from .errors import SecondaryEOBError
from .lifecycle import purge_expired
from .pipeline import process_document
from .session import open_session


def _cmd_init(args: argparse.Namespace) -> int:
    """Create the working root and print the subject to assign a role to."""
    settings = load_settings(args.root)
    settings.ensure_directories()
    (settings.working_root / "config").mkdir(parents=True, exist_ok=True)

    subject, username = current_subject()
    config_path = settings.working_root / "config" / "role_assignments.json"

    print(f"Working root : {settings.working_root}")
    print(f"Encryption   : {'ON' if settings.encryption_enabled else 'OFF (dev mode)'}")
    print(f"Your account : {username}")
    print(f"Your subject : {subject}")
    print()
    if config_path.exists():
        print(f"Role assignments already exist at {config_path}")
    else:
        print("No role assignments yet. Nothing can run until one exists.")
        print(f"Create {config_path} containing, for example:")
        print(json.dumps({subject: "BILLER"}, indent=2))
    return 0


def _cmd_whoami(args: argparse.Namespace) -> int:
    session = open_session(args.root)
    principal = session.principal
    print(f"user        : {principal.username}")
    print(f"subject     : {principal.subject}")
    print(f"role        : {principal.role.value}")
    print("permissions :")
    for permission in sorted(p.value for p in principal.permissions):
        print(f"  - {permission}")
    session.close()
    return 0


def _cmd_process(args: argparse.Namespace) -> int:
    session = open_session(args.root)
    incoming = session.settings.path_for("Incoming")
    sources = sorted(p for p in incoming.iterdir() if p.is_file())

    if not sources:
        print(f"Nothing to process in {incoming}")
        session.close()
        return 0

    exit_code = 0
    for source in sources:
        print(f"\n{source.name}")
        try:
            result = process_document(source, session.guard, session.settings)
        except SecondaryEOBError as exc:
            # Halted and quarantined by the runner; report and continue to
            # the next document rather than abandoning the batch.
            print(f"  HALTED: {exc}")
            exit_code = 1
            continue

        print(f"  job {result.job_id}: {result.patient_count} patient record(s)")
        for outcome in result.outcomes:
            if outcome.exported:
                print(f"  exported {outcome.pseudonym} -> {outcome.exported_path.name}")
            else:
                print(f"  BLOCKED  {outcome.pseudonym}: {outcome.blocked_reason}")
                exit_code = 1

    session.close()
    return exit_code


def _cmd_verify_audit(args: argparse.Namespace) -> int:
    settings = load_settings(args.root)
    path = settings.path_for("Logs") / "audit.jsonl"
    if not path.exists():
        print(f"No audit log at {path}")
        return 1

    log = AuditLog(path)
    try:
        entries = log.verify_chain()
    except SecondaryEOBError as exc:
        print(f"AUDIT CHAIN INVALID: {exc}")
        return 2

    print(f"Audit chain OK: {len(entries)} entries verified")
    if entries:
        print(f"  first : {entries[0].timestamp}")
        print(f"  last  : {entries[-1].timestamp}")
        print(f"  head  : {entries[-1].entry_hash}")
    return 0


def _cmd_purge(args: argparse.Namespace) -> int:
    session = open_session(args.root)
    report = purge_expired(session.guard, session.settings)
    print(f"scanned {report.scanned}, deleted {report.deleted}, failed {report.failed}")
    session.close()
    return 0 if report.clean else 1


def _cmd_status(args: argparse.Namespace) -> int:
    settings = load_settings(args.root)
    settings.ensure_directories()
    print(f"root       : {settings.working_root}")
    print(f"encryption : {'ON' if settings.encryption_enabled else 'OFF (dev mode)'}")
    print(f"api bind   : {settings.api_host}:{settings.api_port}")
    print(
        f"retention  : incoming {settings.incoming_retention_hours}h, "
        f"working {settings.working_retention_hours}h, "
        f"quarantine {settings.quarantine_retention_days}d"
    )
    for name in ("Incoming", "Working", "Ready", "Quarantine"):
        count = sum(1 for p in settings.path_for(name).iterdir() if p.is_file())
        print(f"{name:<11}: {count} file(s)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="secondaryeob",
        description="Local dental EOB processing engine (HIPAA-capable architecture)",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="working root (defaults to $SECONDARYEOB_ROOT)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("init", help="create the working root and show your subject id")
    sub.add_parser("whoami", help="show the resolved identity and role")
    sub.add_parser("process", help="process every document in Incoming/")
    sub.add_parser("verify-audit", help="verify the audit hash chain")
    sub.add_parser("purge", help="run retention deletion")
    sub.add_parser("status", help="show configuration and folder counts")
    return parser


_COMMANDS = {
    "init": _cmd_init,
    "whoami": _cmd_whoami,
    "process": _cmd_process,
    "verify-audit": _cmd_verify_audit,
    "purge": _cmd_purge,
    "status": _cmd_status,
}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return _COMMANDS[args.command](args)
    except SecondaryEOBError as exc:
        # Fail closed and say why, without leaking PHI: every error in the
        # hierarchy is built from identifiers, not document content.
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
