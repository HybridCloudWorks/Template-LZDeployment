#Requires -Version 7.0
# Stage 10 scaffold contract tests. Authored with Stage 10; execution was
# explicitly skipped because the implementation environment lacks the binaries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entry = Get-Content (Join-Path $repo 'scaffold-copy.ps1') -Raw
$shell = Get-Content (Join-Path $repo 'scaffold-copy.sh') -Raw
$module = Get-Content (Join-Path $repo 'factory/scaffold/LZFactory.Scaffold.psm1') -Raw
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw

$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 10 scaffold static contract ==" -ForegroundColor Cyan
ok 'entry is plan-only by default' ($entry -match 'LZ_SCAFFOLD_APPLY')
ok 'shell launcher is strict' ($shell -match 'set -euo pipefail')
ok 'all paths are variable-driven' (
    $entry -match 'LZ_RENDERED_PATH' -and
    $entry -match 'LZ_SCAFFOLD_TARGET' -and
    $entry -match 'LZ_SCAFFOLD_EVIDENCE'
)
ok 'inventory mismatch fails closed' ($module -match 'Rendered inventory mismatch')
ok 'unsafe nested targets fail closed' ($module -match 'must not contain one another')
ok 'non-empty target requires force' ($module -match 'Re-run with -Force')
ok 'existing origin is verified' ($module -match 'Existing origin does not match')
ok 'apply preserves backup' ($module -match 'backupDirectory')
ok 'plan and audit evidence emitted' (
    $module -match 'scaffold-plan\.json' -and $module -match 'scaffold-audit\.json'
)
ok 'user checklist documents scaffold variables' (
    $checklist -match 'LZ_SCAFFOLD_APPLY' -and $checklist -match 'LZ_SCAFFOLD_FORCE'
)
ok 'apply requires the post-render validation report' (
    $module -match 'ValidationReportPath' -and $module -match 'Run \./validate-render\.ps1'
)
ok 'stale validation evidence is rejected' (
    $module -match "'stale'" -and $module -match 'manifestSha256Match'
)
ok 'validation override env is explicit and documented' (
    $module -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED' -and
    $checklist -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED'
)

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
