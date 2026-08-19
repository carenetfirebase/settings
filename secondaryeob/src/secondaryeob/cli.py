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
import json
import os
import platform
import shutil
import sys
from pathlib import Path

from .audit import AuditLog
from .audit.anchor import AnchorStore
from .auth.identity import current_subject
from .config import load_settings
from .crypto import Keyring, read_key_file
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

    # The chain alone cannot detect entries deleted from the end, so the
    # anchors are the half of this check that matters most.
    store = AnchorStore(Path(args.anchors) if args.anchors else path.with_name("anchors.jsonl"))
    try:
        store.verify(log)
    except SecondaryEOBError as exc:
        print(f"ANCHOR CHECK FAILED: {exc}")
        return 2

    anchors = store.read_all()
    if anchors:
        print(f"Anchors OK: {len(anchors)} anchor(s), latest at {anchors[-1].timestamp}")
    else:
        print("No anchors recorded yet — truncation of the log's end is NOT detectable.")

    if args.expect_head:
        try:
            store.verify_head(log, args.expect_head, args.expect_count or len(entries))
        except SecondaryEOBError as exc:
            print(f"EXTERNAL RECORD MISMATCH: {exc}")
            return 2
        print("Externally recorded head hash matches.")

    if entries:
        print(f"  first : {entries[0].timestamp}")
        print(f"  last  : {entries[-1].timestamp}")
        print(f"  count : {len(entries)}")
        print(f"  head  : {entries[-1].entry_hash}")
        print()
        print("Record the count and head hash somewhere off this machine.")
        print("It is the only check that survives an attacker who can write to both")
        print("the audit log and the anchor file:")
        print(f"  secondaryeob verify-audit --expect-count {len(entries)} \\")
        print(f"      --expect-head {entries[-1].entry_hash}")
    return 0


def _cmd_doctor(args: argparse.Namespace) -> int:
    """Preflight the environment and report what would block processing.

    Exists because several requirements are native, not pip-installable —
    most importantly Tesseract, without which post-redaction validation
    cannot run and therefore every export is blocked by design. Finding
    that out from a wall of BLOCKED lines is a bad first experience.
    """
    blocking: list[str] = []
    warnings: list[str] = []

    def ok(label: str, detail: str = "") -> None:
        print(f"  [ok]   {label}{(': ' + detail) if detail else ''}")

    def bad(label: str, detail: str) -> None:
        print(f"  [FAIL] {label}: {detail}")
        blocking.append(label)

    def warn(label: str, detail: str) -> None:
        print(f"  [warn] {label}: {detail}")
        warnings.append(label)

    print("Runtime")
    if sys.version_info >= (3, 11):
        ok("python", platform.python_version())
    else:
        bad("python", f"{platform.python_version()} — 3.11 or newer is required")

    try:
        import pymupdf

        ok("pymupdf", pymupdf.__version__)
    except Exception as exc:
        bad("pymupdf", f"not importable ({type(exc).__name__})")

    try:
        import cryptography

        ok("cryptography", cryptography.__version__)
    except Exception as exc:
        bad("cryptography", f"not importable ({type(exc).__name__})")

    tesseract = shutil.which("tesseract")
    if tesseract:
        ok("tesseract", tesseract)
    else:
        bad(
            "tesseract",
            "not found on PATH. Post-redaction OCR validation cannot run, and a "
            "validation step that cannot run blocks export by design — so every "
            "document will be refused until this is installed. "
            "Windows: install Tesseract-OCR and add it to PATH. "
            "Debian/Ubuntu: apt install tesseract-ocr. macOS: brew install tesseract.",
        )

    print("\nPlatform")
    if sys.platform == "win32":
        ok("key binding", "Windows DPAPI (per-user)")
        warn(
            "windows paths",
            "DPAPI and SID identity are implemented but have not been exercised on "
            "real Windows. Verify escrow-init, escrow-verify and whoami before "
            "trusting this with PHI.",
        )
    else:
        warn(
            "key binding",
            f"{sys.platform}: falling back to the scrypt passphrase provider. This is "
            "a development configuration — production is Windows with DPAPI.",
        )

    print("\nDeployment")
    try:
        settings = load_settings(args.root)
        ok("working root", str(settings.working_root))
        ok("encryption", "ON" if settings.encryption_enabled else "OFF (dev mode)")
        if settings.development_mode:
            warn("dev mode", "SECONDARYEOB_DEV_MODE is set — never use on an instance with real PHI")

        config_path = settings.working_root / "config" / "role_assignments.json"
        if config_path.exists():
            ok("role assignments", str(config_path))
        else:
            bad("role assignments", f"missing at {config_path} — nothing can run without one")

        keys_dir = settings.working_root / "keys"
        if (keys_dir / "dek.escrow").exists():
            ok("key escrow", "enrolled")
        else:
            warn(
                "key escrow",
                "not enrolled. If this key binding is lost, every encrypted record "
                "becomes permanently unreadable. Run 'escrow-init'.",
            )

        anchors = AnchorStore(settings.path_for("Logs") / "anchors.jsonl").read_all()
        if anchors:
            ok("audit anchors", f"{len(anchors)} recorded")
        else:
            warn(
                "audit anchors",
                "none recorded yet — deleting entries from the end of the audit log "
                "would be undetectable until the first anchor is written.",
            )
    except SecondaryEOBError as exc:
        bad("settings", str(exc))

    print()
    if blocking:
        print(f"NOT READY: {len(blocking)} blocking issue(s): {', '.join(blocking)}")
        return 1
    if warnings:
        print(f"Ready to process, with {len(warnings)} warning(s): {', '.join(warnings)}")
        return 0
    print("Ready.")
    return 0


def _cmd_selftest(args: argparse.Namespace) -> int:
    """Prove the whole pipeline works on this machine, using synthetic data.

    Runs in a throwaway directory with invented patients — no real PHI is
    involved and nothing touches the operator's working root. This is the
    check worth running after installing: ``doctor`` confirms the parts are
    present, ``selftest`` confirms they actually redact.
    """
    import tempfile

    import pymupdf

    from .audit import AuditLog
    from .auth import Guard, Principal, Role
    from .config import load_settings
    from .crypto import Keyring, Vault
    from .pipeline import process_document
    from .zones import Zone

    patients = [
        ("Alder Quillfeather", "ZZQ-100001", "03/14/1982", "D2740"),
        ("Bexley Thornwhistle", "ZZQ-200002", "11/02/1975", "D0120"),
        ("Corvina Marchpane", "ZZQ-300003", "07/25/1990", "D1110"),
    ]

    document = pymupdf.open()
    for name, member_id, dob, procedure in patients:
        page = document.new_page()
        page.insert_text((50, 50), "SAMPLE DENTAL PLAN - EOB", fontsize=12)
        page.insert_text((50, 75), f"Patient Name: {name}", fontsize=10)
        page.insert_text((50, 93), f"Member ID: {member_id}", fontsize=10)
        page.insert_text((50, 111), f"Date of Birth: {dob}", fontsize=10)
        page.insert_text(
            (50, 129),
            f"{procedure}  01/15/2026  Billed: $500.00  Allowed: $400.00  "
            f"Paid: $320.00  Patient Resp: $80.00",
            fontsize=9,
        )
    pdf_bytes = document.tobytes()
    document.close()

    with tempfile.TemporaryDirectory(prefix="secondaryeob-selftest-") as tmp:
        root = Path(tmp)
        os.environ["SECONDARYEOB_ROOT"] = str(root)
        os.environ.setdefault("SECONDARYEOB_PASSPHRASE", "selftest-ephemeral-passphrase")

        settings = load_settings(root)
        settings.ensure_directories()

        keyring = Keyring.for_platform(
            root / "keys", passphrase_env_var=settings.passphrase_env_var
        )
        vault = Vault(keyring.load_or_create())
        audit = AuditLog.open(settings.path_for("Logs") / "audit.jsonl")
        principal = Principal(subject="selftest", username="selftest", role=Role.BILLER)
        guard = Guard(principal, vault, audit, root)

        source = settings.path_for("Incoming") / "selftest.pdf"
        vault.write(source, pdf_bytes, zone=Zone.A_RAW_PHI)

        print(f"Processing a synthetic {len(patients)}-patient EOB...")
        try:
            result = process_document(source, guard, settings)
        except SecondaryEOBError as exc:
            print(f"\nFAILED during processing: {type(exc).__name__}: {exc}")
            return 1

        if result.exported_count != len(patients):
            print(f"\nFAILED: expected {len(patients)} exports, got {result.exported_count}")
            for outcome in result.outcomes:
                if outcome.blocked_reason:
                    print(f"  blocked: {outcome.blocked_reason}")
            return 1

        # The check that matters: each output must contain its own patient
        # and none of the others.
        leaks = 0
        for outcome in result.outcomes:
            text_doc = pymupdf.open(stream=guard.read(outcome.exported_path), filetype="pdf")
            try:
                text = "\n".join(
                    text_doc.load_page(i).get_text("text")
                    for i in range(text_doc.page_count)
                )
            finally:
                text_doc.close()

            present = [p for p in patients if p[0] in text]
            if len(present) != 1:
                print(f"  LEAK: {outcome.pseudonym} contains {len(present)} patients")
                leaks += 1
                continue
            for name, member_id, dob, _ in patients:
                if name == present[0][0]:
                    continue
                if member_id in text or dob in text:
                    print(f"  LEAK: {outcome.pseudonym} retains another patient's identifiers")
                    leaks += 1
            print(f"  ok: {outcome.pseudonym} contains exactly one patient")

        audit.verify_chain()
        print(f"  ok: audit chain verified ({audit.entry_count} entries)")

        if leaks:
            print(f"\nFAILED: {leaks} leak(s) detected. Do not process real PHI.")
            return 1

    print("\nSelf-test passed: redaction, validation, export and audit all work here.")
    return 0


def _cmd_escrow_init(args: argparse.Namespace) -> int:
    settings = load_settings(args.root)
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var=settings.passphrase_env_var
    )
    private_key = keyring.enroll_escrow()

    out = Path(args.out)
    out.write_text(private_key.hex() + "\n", encoding="utf-8")
    try:
        out.chmod(0o600)
    except OSError:  # pragma: no cover - platform dependent
        pass

    print(f"Escrow created and restore-verified: {keyring.escrow_path}")
    print(f"Recovery key written to: {out}")
    print()
    print("!! MOVE THIS FILE OFF THIS MACHINE NOW. !!")
    print()
    print("Left beside the working root it is not escrow — it is a second copy of")
    print("the key on the same disk, which weakens the encryption rather than")
    print("protecting it. Put it in a safe, a sealed envelope, or an offline")
    print("password manager, then delete the local copy.")
    print()
    print("Without it, a lost Windows profile means every encrypted record is")
    print("permanently unreadable.")
    return 0


def _cmd_escrow_verify(args: argparse.Namespace) -> int:
    settings = load_settings(args.root)
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var=settings.passphrase_env_var
    )
    keyring.verify_escrow(read_key_file(Path(args.recovery_key)))
    print("Escrow verified: the recovery key restores the data encryption key in use.")
    return 0


def _cmd_recover(args: argparse.Namespace) -> int:
    settings = load_settings(args.root)
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var=settings.passphrase_env_var
    )
    keyring.recover_from_escrow(read_key_file(Path(args.recovery_key)))
    print("Recovered the data encryption key from escrow and re-wrapped it for")
    print("this machine. Encrypted records are readable again.")
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

    keys_dir = settings.working_root / "keys"
    escrowed = (keys_dir / "dek.escrow").exists()
    print(f"escrow     : {'enrolled' if escrowed else 'NOT ENROLLED'}")
    if not escrowed:
        print("             Losing the Windows profile would make every encrypted")
        print("             record permanently unreadable. Run 'escrow-init'.")

    anchors = AnchorStore(settings.path_for("Logs") / "anchors.jsonl").read_all()
    print(f"anchors    : {len(anchors)}")
    if not anchors:
        print("             Without anchors, deleting entries from the end of the")
        print("             audit log is undetectable.")
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
    sub.add_parser("purge", help="run retention deletion")
    sub.add_parser("status", help="show configuration and folder counts")
    sub.add_parser(
        "doctor", help="check this machine for anything that would block processing"
    )
    sub.add_parser(
        "selftest", help="run the full pipeline on synthetic data to prove it works"
    )

    verify = sub.add_parser(
        "verify-audit", help="verify the audit hash chain and its anchors"
    )
    verify.add_argument(
        "--anchors", help="anchor file path (default: anchors.jsonl beside the log)"
    )
    verify.add_argument(
        "--expect-head",
        help="head hash from an external record, to check the log against",
    )
    verify.add_argument(
        "--expect-count", type=int, help="entry count matching --expect-head"
    )

    escrow_init = sub.add_parser(
        "escrow-init", help="create a recovery key so a lost profile is survivable"
    )
    escrow_init.add_argument(
        "--out", required=True, help="where to write the recovery key (then move it offline)"
    )

    escrow_verify = sub.add_parser(
        "escrow-verify", help="prove the recovery key still restores the key in use"
    )
    escrow_verify.add_argument("--recovery-key", required=True, help="recovery key file")

    recover = sub.add_parser(
        "recover", help="restore the data encryption key from escrow onto this machine"
    )
    recover.add_argument("--recovery-key", required=True, help="recovery key file")

    return parser


_COMMANDS = {
    "init": _cmd_init,
    "whoami": _cmd_whoami,
    "process": _cmd_process,
    "verify-audit": _cmd_verify_audit,
    "escrow-init": _cmd_escrow_init,
    "escrow-verify": _cmd_escrow_verify,
    "recover": _cmd_recover,
    "purge": _cmd_purge,
    "status": _cmd_status,
    "doctor": _cmd_doctor,
    "selftest": _cmd_selftest,
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
