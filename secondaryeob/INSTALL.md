# Installing SecondaryEOB

Three routes, in order of how much they assume about the machine. All of
them still need **Tesseract-OCR** — see below, it is not optional.

> **Windows status.** The production target is Windows, and the Windows
> code paths (DPAPI key wrapping, SID identity) have been written and
> reviewed but **never executed** — development and testing were on Linux.
> Run `secondaryeob selftest` and `secondaryeob whoami` immediately after
> installing, before trusting it with anything real.

---

## Route 1 — the install script (recommended)

Clone, then run the installer for your platform. It checks Python, offers
to install Tesseract, creates an isolated virtual environment, installs
the package, and then **verifies the result by actually redacting a
synthetic document**.

### Windows (PowerShell)

```powershell
git clone <repo-url>
cd settings\secondaryeob

# If script execution is blocked:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\install.ps1
```

Useful switches:

```powershell
.\install.ps1 -InstallDir D:\Apps\SecondaryEOB -WorkingRoot D:\EOBWork
.\install.ps1 -AssignRole BILLER      # unattended; skips the role prompt
.\install.ps1 -SkipTesseract          # every export will be BLOCKED
```

### Linux / macOS

```bash
git clone <repo-url>
cd settings/secondaryeob
export SECONDARYEOB_PASSPHRASE='choose-something-strong'   # no DPAPI off Windows
./install.sh
```

```bash
./install.sh --install-dir ~/apps/seob --working-root ~/eob-work
./install.sh --assign-role BILLER      # unattended
```

---

## Route 2 — pip, into your own environment

```bash
python -m venv venv
venv/bin/pip install ./dist/secondaryeob-0.1.0-py3-none-any.whl   # or:
venv/bin/pip install .                                            # from source
venv/bin/secondaryeob selftest
```

The wheel is `py3-none-any` — the same file installs on Windows, Linux and
macOS. Requires Python 3.11+.

---

## Route 3 — standalone executable (no Python on the target)

Bundles Python and every Python dependency into one file.

**Must be built on the platform it will run on.** PyInstaller is not a
cross-compiler, so a Windows `.exe` has to be built on Windows.

```powershell
.\packaging\build-exe.ps1          # Windows -> dist-exe\secondaryeob.exe
```

```bash
pyinstaller packaging/secondaryeob.spec --clean --noconfirm
./dist/secondaryeob selftest
```

The build script runs the self-test before declaring success, because a
frozen binary can import cleanly and still be missing a lazily-imported
module.

Verified: a 39 MB Linux binary running the full pipeline on a machine with
no source tree and no Python on PATH. The Windows equivalent is untested —
see the status note above.

---

## Tesseract-OCR — required, and not installed by pip

Post-redaction validation re-reads every page with OCR to confirm the PHI
is really gone. **A validation step that cannot run blocks export by
design**, so without Tesseract every document is refused. This is
deliberate — "we didn't look" is not "we looked and found nothing" — but
it means a machine without Tesseract processes nothing at all.

| Platform | Install |
|---|---|
| Windows | `winget install UB-Mannheim.TesseractOCR`, or [the UB-Mannheim installer](https://github.com/UB-Mannheim/tesseract/wiki) |
| Debian/Ubuntu | `sudo apt install tesseract-ocr` |
| Fedora | `sudo dnf install tesseract` |
| macOS | `brew install tesseract` |

On Windows, make sure the install directory (usually
`C:\Program Files\Tesseract-OCR`) is on `PATH`. `secondaryeob doctor`
tells you whether it can be found.

---

## After installing

```bash
secondaryeob doctor      # is anything missing or misconfigured?
secondaryeob selftest    # does redaction actually work here?
```

`doctor` checks the parts are present. `selftest` builds a synthetic
three-patient EOB, runs the whole pipeline, and confirms each output holds
exactly one patient and none of the others' identifiers. It uses invented
data and a throwaway directory — no real PHI, and it does not touch your
working root. **If `selftest` fails, do not process real documents.**

Then, in order:

```bash
# 1. A role, if the installer did not set one. Nothing runs without it.
#    secondaryeob init  prints the subject id to use.
#    {"<subject>": "BILLER"}  ->  <working-root>/config/role_assignments.json

# 2. A recovery key — then MOVE IT OFF THE MACHINE.
secondaryeob escrow-init --out recovery.key
```

Escrow matters more than it sounds: the encryption key is bound to the
Windows profile, so without a recovery key held elsewhere, losing that
profile makes every encrypted record permanently unreadable. Left next to
the working root it is not escrow — it is a second copy of the key on the
same disk.

```bash
# 3. Process.
secondaryeob process

# 4. Verify the audit trail, and file the head hash somewhere off-machine.
secondaryeob verify-audit
```

That last step is not ceremony. The audit chain cannot detect entries
deleted from its *end*; anchors catch that, and a head hash recorded
outside the machine is the only check that still holds if someone can
write to both the log and the anchors.

---

## Uninstalling

Delete the install directory (`%LOCALAPPDATA%\SecondaryEOB` or
`~/.local/share/secondaryeob`). The working root is separate and holds
your data — delete it deliberately, and note that removing it while a
recovery key still exists elsewhere leaves that key useless but harmless.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every document `BLOCKED ... ocr_rescan could not run` | Tesseract missing from `PATH`. |
| `ConfigError: no role assignments` | No role assigned yet — see step 1. |
| `UnsafeWorkingDirectoryError` | Working root is inside OneDrive/Dropbox/etc. A sync client copies PHI off the machine outside every control here. Move it to local storage. |
| `ConfigError: SECONDARYEOB_ROOT is not set` | Set it, or pass `--root`. It is never guessed. |
| `EncryptionError: could not unwrap the DEK` | Wrong passphrase, or the Windows profile changed. Recover with `secondaryeob recover --recovery-key recovery.key`. |
| `AUDIT LOG TRUNCATED` / `HISTORY REWRITTEN` | Entries were deleted or the log rebuilt. Investigate before processing further. |
| `ExtractionError: no text layer` | A scanned PDF. OCR-for-extraction is not implemented yet; the document quarantines rather than being processed blind. |
