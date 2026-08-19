"""Test fixtures.

**Synthetic data only** (master prompt §14: never process production PHI
during testing). Every name, member ID, and date of birth in this file is
invented for the test suite. Nothing here came from a real EOB, and no
test in this suite reads from a path outside its own tmp_path.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pymupdf
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from secondaryeob.auth import Guard, Principal, Role  # noqa: E402
from secondaryeob.audit import AuditLog  # noqa: E402
from secondaryeob.config import load_settings  # noqa: E402
from secondaryeob.crypto import Keyring, Vault  # noqa: E402

TEST_PASSPHRASE = "test-passphrase-not-a-real-secret"


#: Invented patients. Distinct surnames and ID formats so a leak from one
#: record into another's output is unambiguous.
SYNTHETIC_PATIENTS = [
    {
        "name": "Alder Quillfeather",
        "member_id": "ZZQ-100001",
        "dob": "03/14/1982",
        "procedure": "D2740",
        "billed": "1,250.00",
        "allowed": "980.00",
        "paid": "784.00",
        "patient_resp": "196.00",
    },
    {
        "name": "Bexley Thornwhistle",
        "member_id": "ZZQ-200002",
        "dob": "11/02/1975",
        "procedure": "D0120",
        "billed": "95.00",
        "allowed": "72.00",
        "paid": "57.60",
        "patient_resp": "14.40",
    },
    {
        "name": "Corvina Marchpane",
        "member_id": "ZZQ-300003",
        "dob": "07/25/1990",
        "procedure": "D1110",
        "billed": "130.00",
        "allowed": "104.00",
        "paid": "83.20",
        "patient_resp": "20.80",
    },
]


def build_eob_pdf(patients: list[dict], *, one_page_each: bool = True) -> bytes:
    """Render a synthetic multi-patient EOB PDF.

    Args:
        one_page_each: When True each patient gets their own page. When
            False all patients share a single page, which is the harder
            redaction case — the output must keep the page and remove the
            other patients' lines from it.
    """
    document = pymupdf.open()

    def write_patient(page, top: float, patient: dict) -> float:
        y = top
        lines = [
            f"Patient Name: {patient['name']}",
            f"Member ID: {patient['member_id']}",
            f"Date of Birth: {patient['dob']}",
            f"{patient['procedure']}  01/15/2026  Billed: ${patient['billed']}  "
            f"Allowed: ${patient['allowed']}  Paid: ${patient['paid']}  "
            f"Patient Resp: ${patient['patient_resp']}",
        ]
        for line in lines:
            page.insert_text((50, y), line, fontsize=10, fontname="helv")
            y += 18
        return y + 12

    if one_page_each:
        for patient in patients:
            page = document.new_page()
            page.insert_text((50, 40), "SAMPLE DENTAL PLAN - EOB", fontsize=12, fontname="hebo")
            write_patient(page, 80, patient)
    else:
        page = document.new_page()
        page.insert_text((50, 40), "SAMPLE DENTAL PLAN - EOB", fontsize=12, fontname="hebo")
        y = 80
        for patient in patients:
            y = write_patient(page, y, patient)

    data = document.tobytes()
    document.close()
    return data


@pytest.fixture
def eob_pdf() -> bytes:
    """A three-patient EOB, one page per patient."""
    return build_eob_pdf(SYNTHETIC_PATIENTS)


@pytest.fixture
def shared_page_eob_pdf() -> bytes:
    """A three-patient EOB with all patients on one shared page."""
    return build_eob_pdf(SYNTHETIC_PATIENTS, one_page_each=False)


@pytest.fixture
def working_root(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """An initialised working root with settings pointing at it."""
    root = tmp_path / "seob"
    monkeypatch.setenv("SECONDARYEOB_ROOT", str(root))
    monkeypatch.setenv("SECONDARYEOB_PASSPHRASE", TEST_PASSPHRASE)
    monkeypatch.delenv("SECONDARYEOB_DEV_MODE", raising=False)
    monkeypatch.delenv("SECONDARYEOB_ENCRYPTION", raising=False)
    settings = load_settings()
    settings.ensure_directories()
    return root


@pytest.fixture
def settings(working_root: Path):
    return load_settings(working_root)


@pytest.fixture
def audit_log(settings) -> AuditLog:
    return AuditLog.open(settings.path_for("Logs") / "audit.jsonl")


@pytest.fixture
def vault(settings) -> Vault:
    keyring = Keyring.for_platform(
        settings.working_root / "keys", passphrase_env_var="SECONDARYEOB_PASSPHRASE"
    )
    return Vault(keyring.load_or_create())


def make_guard(settings, vault: Vault, audit: AuditLog, role: Role) -> Guard:
    """Build a guard for a synthetic principal holding ``role``."""
    principal = Principal(subject=f"test:{role.value}", username=f"test-{role.value.lower()}", role=role)
    return Guard(principal, vault, audit, settings.working_root)


@pytest.fixture
def biller_guard(settings, vault, audit_log) -> Guard:
    return make_guard(settings, vault, audit_log, Role.BILLER)


@pytest.fixture
def reviewer_guard(settings, vault, audit_log) -> Guard:
    return make_guard(settings, vault, audit_log, Role.REVIEWER)


@pytest.fixture
def admin_guard(settings, vault, audit_log) -> Guard:
    return make_guard(settings, vault, audit_log, Role.ADMIN)


@pytest.fixture
def role_config(working_root: Path):
    """Write a role assignment file for the current OS account."""
    config_dir = working_root / "config"
    config_dir.mkdir(parents=True, exist_ok=True)
    subject = f"posix:{os.getuid()}:{__import__('getpass').getuser()}"
    (config_dir / "role_assignments.json").write_text(
        json.dumps({subject: "BILLER"}), encoding="utf-8"
    )
    return config_dir
