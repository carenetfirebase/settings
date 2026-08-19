<#
.SYNOPSIS
    Install SecondaryEOB on Windows into a self-contained virtual environment.

.DESCRIPTION
    Creates a venv, installs the package into it, and verifies the result
    with the built-in preflight and self-test. Does not touch the system
    Python installation beyond creating the venv.

    Tesseract-OCR is a hard requirement: post-redaction validation reads
    each page back with OCR, and a validation step that cannot run blocks
    export by design. Without it every document is refused. This script
    offers to install it via winget.

.PARAMETER InstallDir
    Where to create the virtual environment.
    Default: %LOCALAPPDATA%\SecondaryEOB

.PARAMETER WorkingRoot
    Where PHI-bearing folders live. This must be local, non-synced storage
    — the application refuses to start inside OneDrive/Dropbox/etc.
    Default: %LOCALAPPDATA%\SecondaryEOB\work

.PARAMETER SkipTesseract
    Do not offer to install Tesseract. The install will complete but every
    export will be blocked until Tesseract is on PATH.

.PARAMETER AssignRole
    Grant this Windows account the given role without prompting. Use for
    unattended installs. Not the default, because BILLER can read raw PHI
    and that should be a deliberate choice.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstallDir D:\Apps\SecondaryEOB -WorkingRoot D:\EOB
    .\install.ps1 -AssignRole BILLER
#>
[CmdletBinding()]
param(
    [string]$InstallDir  = "$env:LOCALAPPDATA\SecondaryEOB",
    [string]$WorkingRoot = "$env:LOCALAPPDATA\SecondaryEOB\work",
    [switch]$SkipTesseract,
    [ValidateSet('ADMIN','BILLER','REVIEWER')]
    [string]$AssignRole
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [ok]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Python -----------------------------------------------------------
Write-Step "Checking Python"

$python = $null
foreach ($candidate in @('py -3.13','py -3.12','py -3.11','python','python3')) {
    $parts = $candidate.Split(' ')
    $exe   = $parts[0]
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
    try {
        $ver = & $exe @($parts[1..($parts.Length-1)] + @('-c','import sys;print("%d.%d"%sys.version_info[:2])')) 2>$null
    } catch { continue }
    if (-not $ver) { continue }
    $major, $minor = $ver.Trim().Split('.')
    if ([int]$major -eq 3 -and [int]$minor -ge 11) {
        $python = $candidate
        Write-Ok "Python $ver via '$candidate'"
        break
    }
}

if (-not $python) {
    Write-Bad "No Python 3.11+ found."
    Write-Host ""
    Write-Host "  Install it, then re-run this script:"
    Write-Host "    winget install Python.Python.3.12"
    Write-Host "  or download from https://www.python.org/downloads/windows/"
    Write-Host "  (tick 'Add python.exe to PATH' in the installer)"
    exit 1
}

# --- Tesseract --------------------------------------------------------
Write-Step "Checking Tesseract-OCR"

$tesseract = Get-Command tesseract -ErrorAction SilentlyContinue
if ($tesseract) {
    Write-Ok "tesseract at $($tesseract.Source)"
} elseif ($SkipTesseract) {
    Write-Warn "Tesseract missing and -SkipTesseract given. Every export will be BLOCKED."
} else {
    Write-Warn "Tesseract not found on PATH."
    Write-Host ""
    Write-Host "  Post-redaction validation re-reads each page with OCR to confirm the"
    Write-Host "  PHI really is gone. A validation step that cannot run blocks export by"
    Write-Host "  design, so without Tesseract every document is refused."
    Write-Host ""

    $installed = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $answer = Read-Host "  Install Tesseract now via winget? [Y/n]"
        if ($answer -eq '' -or $answer -match '^[Yy]') {
            winget install --id UB-Mannheim.TesseractOCR --accept-source-agreements --accept-package-agreements
            $installed = $true
        }
    }

    if ($installed) {
        # winget does not refresh this shell's PATH; look in the default location.
        $default = "$env:ProgramFiles\Tesseract-OCR"
        if (Test-Path "$default\tesseract.exe") {
            $env:PATH = "$default;$env:PATH"
            Write-Ok "tesseract installed at $default"
            Write-Warn "Added to PATH for this session only. Add it permanently:"
            Write-Host "    setx PATH `"%PATH%;$default`""
        } else {
            Write-Warn "Installed, but not found in the default location. Open a NEW terminal and re-run."
        }
    } else {
        Write-Warn "Skipping. Install later from https://github.com/UB-Mannheim/tesseract/wiki"
    }
}

# --- Virtual environment ---------------------------------------------
Write-Step "Creating the virtual environment"

if (Test-Path "$InstallDir\Scripts\python.exe") {
    Write-Ok "Reusing existing venv at $InstallDir"
} else {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $pyParts = $python.Split(' ')
    & $pyParts[0] @($pyParts[1..($pyParts.Length-1)] + @('-m','venv',$InstallDir))
    if ($LASTEXITCODE -ne 0) { Write-Bad "venv creation failed"; exit 1 }
    Write-Ok "Created $InstallDir"
}

$venvPython = "$InstallDir\Scripts\python.exe"
$venvExe    = "$InstallDir\Scripts\secondaryeob.exe"

# --- Install ----------------------------------------------------------
Write-Step "Installing SecondaryEOB"

& $venvPython -m pip install --quiet --upgrade pip
if ($LASTEXITCODE -ne 0) { Write-Bad "could not upgrade pip"; exit 1 }

# Prefer a prebuilt wheel next to this script; fall back to the source tree.
$wheel = Get-ChildItem -Path "$scriptDir\dist" -Filter 'secondaryeob-*.whl' -ErrorAction SilentlyContinue |
         Sort-Object Name -Descending | Select-Object -First 1

if ($wheel) {
    Write-Host "  installing $($wheel.Name)"
    & $venvPython -m pip install --quiet --force-reinstall $wheel.FullName
} else {
    Write-Host "  no wheel in dist\, installing from source"
    & $venvPython -m pip install --quiet --force-reinstall $scriptDir
}
if ($LASTEXITCODE -ne 0) { Write-Bad "installation failed"; exit 1 }
Write-Ok "installed"

# --- Verify -----------------------------------------------------------
Write-Step "Self-test (synthetic data, no PHI)"
& $venvExe selftest
$selftestExit = $LASTEXITCODE

# --- Role assignment --------------------------------------------------
Write-Step "Role assignment"
$env:SECONDARYEOB_ROOT = $WorkingRoot
& $venvExe init | Out-Null

$roleFile = "$WorkingRoot\config\role_assignments.json"
$subject  = (& $venvExe init | Select-String '^Your subject') -replace '^Your subject\s*:\s*',''
$subject  = $subject.Trim()

function Write-RoleFile($role) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $roleFile) | Out-Null
    # ASCII, no BOM: the loader parses this as JSON and a BOM breaks it.
    [System.IO.File]::WriteAllText($roleFile, "{`n  `"$subject`": `"$role`"`n}`n")
    Write-Ok "assigned $role to $subject"
}

if (Test-Path $roleFile) {
    Write-Ok "already assigned ($roleFile)"
} elseif (-not $subject) {
    Write-Warn "could not determine this account's SID; assign a role by hand"
} elseif ($AssignRole) {
    Write-RoleFile $AssignRole
} else {
    Write-Host "  BILLER can read raw PHI, redact, and export. That is the production"
    Write-Host "  role; ADMIN and REVIEWER deliberately cannot do all three."
    Write-Host ""
    $answer = Read-Host "  Assign $subject the BILLER role? [Y/n]"
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        Write-RoleFile 'BILLER'
    } else {
        Write-Warn "skipped. Nothing will run until $roleFile exists."
    }
}

Write-Step "Preflight"
& $venvExe doctor
$doctorExit = $LASTEXITCODE

# --- Next steps -------------------------------------------------------
Write-Step "Next steps"

Write-Host @"
  1. Create a recovery key, then MOVE IT OFF THIS MACHINE:

       $venvExe escrow-init --out recovery.key

     Without it, losing this Windows profile makes every encrypted record
     permanently unreadable.

  2. Add to PATH so you can just type 'secondaryeob':

       setx PATH "%PATH%;$InstallDir\Scripts"

  3. Drop bulk EOB PDFs in $WorkingRoot\Incoming and run:

       secondaryeob process

  4. After each batch, verify the audit trail and file the head hash
     somewhere off this machine:

       secondaryeob verify-audit
"@

if ($selftestExit -ne 0) { Write-Bad "SELF-TEST FAILED — do not process real PHI."; exit 1 }
if ($doctorExit  -ne 0) { Write-Warn "Preflight reported blocking issues (see above)."; exit 1 }

Write-Host ""
Write-Ok "Install complete."
