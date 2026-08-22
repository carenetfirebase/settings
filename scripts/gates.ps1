# The four quality gates from CLAUDE.md, in order.
# PowerShell 7. No && chaining -- see CLAUDE.md environment notes.
$fail = 0
function Invoke-Gate($name, $block) {
    Write-Host "=== $name ===" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0) { $script:fail = 1 }
    Write-Host ""
}
Invoke-Gate "ruff format" { uv run ruff format --check . }
Invoke-Gate "ruff check"  { uv run ruff check . }
Invoke-Gate "mypy"        { uv run mypy src/imt }
Invoke-Gate "pytest"      { uv run pytest -q }
Push-Location frontend
Invoke-Gate "frontend"    { npx vitest run }
Pop-Location
exit $fail
