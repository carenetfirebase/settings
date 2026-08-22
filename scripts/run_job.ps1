# Windows Task Scheduler entrypoint.
#
# Task Scheduler launches with an arbitrary working directory and a minimal
# PATH, so this resolves the repo root and `uv` explicitly rather than
# assuming either. A job that silently fails to start is worse than one that
# errors, so every failure path writes to the log and returns non-zero.
param(
    [Parameter(Mandatory = $true)][string[]]$Command
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
    $candidate = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
    if (Test-Path $candidate) { $uv = $candidate } else {
        Write-Error "uv not found on PATH or at $candidate"
        exit 1
    }
} else { $uv = $uv.Source }

$logDir = Join-Path $repo "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("imt-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

"$(Get-Date -Format o) START imt $($Command -join ' ')" | Add-Content $log
& $uv run imt @Command 2>&1 | Tee-Object -Append -FilePath $log
$code = $LASTEXITCODE
"$(Get-Date -Format o) END   exit=$code" | Add-Content $log
exit $code
