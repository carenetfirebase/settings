<#
.SYNOPSIS
    Build a standalone secondaryeob.exe on Windows.

.DESCRIPTION
    Produces a single executable that bundles Python and all Python
    dependencies, so the target machine needs neither installed.

    Must run ON Windows: PyInstaller is not a cross-compiler, so a Windows
    .exe cannot be produced from Linux or macOS.

    Tesseract-OCR is still required separately on the target machine. It is
    a native program, not a Python dependency, and post-redaction
    validation cannot run without it — which blocks every export by design.

.EXAMPLE
    .\packaging\build-exe.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDir = "dist-exe"
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Host "This script builds a Windows .exe and must run on Windows." -ForegroundColor Red
    Write-Host "On Linux/macOS use: pyinstaller packaging/secondaryeob.spec"
    exit 1
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    Write-Host "=== Installing build dependencies ===" -ForegroundColor Cyan
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet ".[build]"

    Write-Host "`n=== Building ===" -ForegroundColor Cyan
    python -m PyInstaller packaging/secondaryeob.spec `
        --clean --noconfirm `
        --distpath $OutputDir `
        --workpath build/pyinstaller

    $exe = Join-Path $OutputDir "secondaryeob.exe"
    if (-not (Test-Path $exe)) {
        Write-Host "Build reported success but $exe is missing." -ForegroundColor Red
        exit 1
    }

    # A frozen build that imports cleanly can still be missing a module
    # that is only imported lazily, so exercise the real pipeline rather
    # than just --help.
    Write-Host "`n=== Verifying the binary ===" -ForegroundColor Cyan
    $env:SECONDARYEOB_ROOT = Join-Path $env:TEMP "secondaryeob-buildcheck"
    & $exe selftest
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Self-test FAILED — the binary is not usable." -ForegroundColor Red
        exit 1
    }

    $size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Write-Host "`nBuilt $exe ($size MB)" -ForegroundColor Green
    Write-Host "Remember: Tesseract-OCR must still be installed on the target machine."
} finally {
    Pop-Location
}
