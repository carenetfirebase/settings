#!/usr/bin/env bash
#
# Install SecondaryEOB into a self-contained virtual environment.
#
# For Linux/macOS. The production target is Windows (use install.ps1);
# this exists for development and for evaluating the pipeline.
#
# Usage:
#   ./install.sh [--install-dir DIR] [--working-root DIR] [--skip-tesseract]
#                [--assign-role ADMIN|BILLER|REVIEWER]
#
# --assign-role grants this OS account that role without prompting. Use it
# for unattended installs; it is not the default because BILLER can read
# raw PHI and that should be a deliberate choice.

set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/secondaryeob"
WORKING_ROOT="${HOME}/secondaryeob-work"
SKIP_TESSERACT=0
ASSIGN_ROLE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)    INSTALL_DIR="$2"; shift 2 ;;
        --working-root)   WORKING_ROOT="$2"; shift 2 ;;
        --skip-tesseract) SKIP_TESSERACT=1; shift ;;
        --assign-role)    ASSIGN_ROLE="$2"; shift 2 ;;
        -h|--help)        sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; }

# --- Python -----------------------------------------------------------
step "Checking Python"

PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3 python; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    version="$("$candidate" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || true)"
    [[ -n "$version" ]] || continue
    major="${version%%.*}"; minor="${version##*.}"
    if [[ "$major" -eq 3 && "$minor" -ge 11 ]]; then
        PYTHON="$candidate"; ok "Python $version ($candidate)"; break
    fi
done

if [[ -z "$PYTHON" ]]; then
    bad "No Python 3.11+ found."
    echo "  Debian/Ubuntu: sudo apt install python3.12 python3.12-venv"
    echo "  macOS:         brew install python@3.12"
    exit 1
fi

# --- Tesseract --------------------------------------------------------
step "Checking Tesseract-OCR"

if command -v tesseract >/dev/null 2>&1; then
    ok "tesseract at $(command -v tesseract)"
elif [[ "$SKIP_TESSERACT" -eq 1 ]]; then
    warn "Tesseract missing and --skip-tesseract given. Every export will be BLOCKED."
else
    warn "Tesseract not found on PATH."
    echo
    echo "  Post-redaction validation re-reads each page with OCR to confirm the PHI"
    echo "  really is gone. A validation step that cannot run blocks export by design,"
    echo "  so without Tesseract every document is refused."
    echo
    if command -v apt-get >/dev/null 2>&1; then
        echo "    sudo apt install tesseract-ocr"
    elif command -v brew >/dev/null 2>&1; then
        echo "    brew install tesseract"
    elif command -v dnf >/dev/null 2>&1; then
        echo "    sudo dnf install tesseract"
    fi
    echo
fi

# --- Virtual environment ---------------------------------------------
step "Creating the virtual environment"

if [[ -x "${INSTALL_DIR}/bin/python" ]]; then
    ok "Reusing existing venv at ${INSTALL_DIR}"
else
    mkdir -p "$INSTALL_DIR"
    "$PYTHON" -m venv "$INSTALL_DIR"
    ok "Created ${INSTALL_DIR}"
fi

VENV_PY="${INSTALL_DIR}/bin/python"
VENV_EXE="${INSTALL_DIR}/bin/secondaryeob"

# --- Install ----------------------------------------------------------
step "Installing SecondaryEOB"

"$VENV_PY" -m pip install --quiet --upgrade pip

wheel="$(ls -1 "${SCRIPT_DIR}"/dist/secondaryeob-*.whl 2>/dev/null | sort | tail -1 || true)"
if [[ -n "$wheel" ]]; then
    echo "  installing $(basename "$wheel")"
    "$VENV_PY" -m pip install --quiet --force-reinstall "$wheel"
else
    echo "  no wheel in dist/, installing from source"
    "$VENV_PY" -m pip install --quiet --force-reinstall "$SCRIPT_DIR"
fi
ok "installed"

# --- Verify -----------------------------------------------------------
step "Self-test (synthetic data, no PHI)"
selftest_exit=0
"$VENV_EXE" selftest || selftest_exit=$?

step "Role assignment"
export SECONDARYEOB_ROOT="$WORKING_ROOT"
"$VENV_EXE" init >/dev/null 2>&1 || true

role_file="${WORKING_ROOT}/config/role_assignments.json"
subject="$("$VENV_EXE" init 2>/dev/null | sed -n 's/^Your subject *: *//p' || true)"

if [[ -f "$role_file" ]]; then
    ok "already assigned ($role_file)"
elif [[ -z "$subject" ]]; then
    warn "could not determine this account's subject id; assign a role by hand"
elif [[ -n "$ASSIGN_ROLE" ]]; then
    mkdir -p "$(dirname "$role_file")"
    printf '{\n  "%s": "%s"\n}\n' "$subject" "$ASSIGN_ROLE" > "$role_file"
    chmod 600 "$role_file" 2>/dev/null || true
    ok "assigned ${ASSIGN_ROLE} to ${subject} (--assign-role)"
elif [[ ! -t 0 ]]; then
    # Non-interactive: never grant PHI access without someone saying so.
    warn "non-interactive and no --assign-role given, so no role was assigned."
    echo "         Create $role_file yourself, or re-run with --assign-role BILLER."
else
    echo "  BILLER can read raw PHI, redact, and export. That is the production"
    echo "  role; ADMIN and REVIEWER deliberately cannot do all three."
    echo
    read -r -p "  Assign ${subject} the BILLER role? [Y/n] " answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
        mkdir -p "$(dirname "$role_file")"
        printf '{\n  "%s": "BILLER"\n}\n' "$subject" > "$role_file"
        chmod 600 "$role_file" 2>/dev/null || true
        ok "assigned BILLER to ${subject}"
    else
        warn "skipped. Nothing will run until $role_file exists."
    fi
fi

step "Preflight"
# Off Windows there is no DPAPI, so the key is wrapped with a passphrase.
export SECONDARYEOB_PASSPHRASE="${SECONDARYEOB_PASSPHRASE:-}"
if [[ -z "$SECONDARYEOB_PASSPHRASE" ]]; then
    warn "SECONDARYEOB_PASSPHRASE is not set — required off Windows to wrap the key."
    echo "         export SECONDARYEOB_PASSPHRASE='...' before running commands."
fi
doctor_exit=0
"$VENV_EXE" doctor || doctor_exit=$?

# --- Next steps -------------------------------------------------------
step "Next steps"

cat <<EOF
  1. Create a recovery key, then MOVE IT OFF THIS MACHINE:

       ${VENV_EXE} escrow-init --out recovery.key

     Without it, losing this key binding makes every encrypted record
     permanently unreadable.

  2. Put it on PATH:

       export PATH="${INSTALL_DIR}/bin:\$PATH"

  3. Drop bulk EOB PDFs in ${WORKING_ROOT}/Incoming and run:

       secondaryeob process

  4. After each batch, verify the audit trail and file the head hash
     somewhere off this machine:

       secondaryeob verify-audit
EOF

if [[ "$selftest_exit" -ne 0 ]]; then bad "SELF-TEST FAILED — do not process real PHI."; exit 1; fi
if [[ "$doctor_exit"  -ne 0 ]]; then warn "Preflight reported blocking issues (see above)."; exit 1; fi

echo
ok "Install complete."
