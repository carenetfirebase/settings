# PyInstaller spec — standalone SecondaryEOB executable.
#
# Build:
#   pip install pyinstaller
#   pyinstaller packaging/secondaryeob.spec --clean --noconfirm
#
# Output: dist/secondaryeob (dist\secondaryeob.exe on Windows)
#
# PyInstaller is NOT a cross-compiler. A Windows .exe must be built on
# Windows, a Linux binary on Linux. This spec is platform-neutral so the
# same file serves both.
#
# What this does and does not remove as a dependency:
#   - Python: bundled. The target machine does not need it installed.
#   - cryptography / pymupdf: bundled, including their native libraries.
#   - Tesseract: NOT bundled. It is a separate native program invoked
#     through PyMuPDF, and it still has to be installed and on PATH.
#     Without it, post-redaction validation cannot run and every export
#     is blocked by design. A standalone binary does not change that.

import os
import sys

from PyInstaller.utils.hooks import collect_dynamic_libs, collect_submodules

block_cipher = None

# Resolve paths against the spec file, never the working directory:
# PyInstaller is normally invoked from the project root, so a relative
# "../src" silently resolves one level too high and the package is left
# out of the bundle entirely. The build still succeeds; the binary then
# dies with ModuleNotFoundError on first run.
SRC = os.path.abspath(os.path.join(SPECPATH, os.pardir, "src"))
ENTRYPOINT = os.path.join(SPECPATH, "entrypoint.py")

if not os.path.isdir(SRC):
    raise SystemExit(f"source tree not found at {SRC}")

# collect_submodules imports the package through the build-time
# interpreter, so it has to be importable here too — not merely on
# PyInstaller's analysis path.
if SRC not in sys.path:
    sys.path.insert(0, SRC)

# cryptography loads its Rust extension dynamically; pymupdf carries
# libmupdf. Neither is reliably picked up by static analysis alone.
binaries = collect_dynamic_libs("cryptography") + collect_dynamic_libs("pymupdf")

hiddenimports = [
    # Imported lazily inside functions, so the analyser does not see them.
    "secondaryeob.crypto.escrow",
    "secondaryeob.audit.anchor",
    # cryptography's backend chain.
    "cryptography.hazmat.bindings._rust",
    "cryptography.hazmat.backends.openssl",
    *collect_submodules("secondaryeob"),
]

a = Analysis(
    [ENTRYPOINT],
    pathex=[SRC],
    binaries=binaries,
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # Trimming the GUI stacks keeps the binary from ballooning; this is a
    # console application and pulls in none of them.
    excludes=["tkinter", "PyQt5", "PyQt6", "PySide2", "PySide6", "matplotlib", "IPython"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="secondaryeob",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    # UPX is off deliberately: compressed executables are a common
    # antivirus false-positive trigger, and this binary handles PHI on
    # clinical workstations where a quarantine event is disruptive.
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
