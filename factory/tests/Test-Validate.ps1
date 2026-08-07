#Requires -Version 7.0
# Post-render validation gate static contract tests. Like Test-Scaffold.ps1,
# these assert the contract in the source text so they run without terraform,
# tflint, or a scanner installed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entry = Get-Content (Join-Path $repo 'validate-render.ps1') -Raw
$shell = Get-Content (Join-Path $repo 'validate-render.sh') -Raw
$module = Get-Content (Join-Path $repo 'factory/validate/LZFactory.Validate.psm1') -Raw
$scaffoldModule = Get-Content (Join-Path $repo 'factory/scaffold/LZFactory.Scaffold.psm1') -Raw
$scaffoldEntry = Get-Content (Join-Path $repo 'scaffold-copy.ps1') -Raw
$wrapper = Get-Content (Join-Path $repo 'scripts/Invoke-CustomerEngagement.ps1') -Raw
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw
$gitignore = Get-Content (Join-Path $repo '.gitignore') -Raw

$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Post-render validation gate static contract ==" -ForegroundColor Cyan
ok 'entry paths are variable-driven' (
    $entry -match 'LZ_RENDERED_PATH' -and
    $entry -match 'LZ_VALIDATE_EVIDENCE'
)
ok 'entry honors strict and skip variables' (
    $entry -match 'LZ_VALIDATE_STRICT' -and
    $entry -match 'LZ_VALIDATE_SKIP_SECURITY_SCAN' -and
    $entry -match 'LZ_VALIDATE_SKIP_LINT'
)
ok 'shell launcher is strict' ($shell -match 'set -euo pipefail')
ok 'shell launcher forwards strict and skip variables' (
    $shell -match 'LZ_VALIDATE_STRICT' -and
    $shell -match 'LZ_VALIDATE_SKIP_SECURITY_SCAN' -and
    $shell -match 'LZ_VALIDATE_SKIP_LINT'
)
ok 'all eight gates are present' (
    @('V01', 'V02', 'V03', 'V04', 'V05', 'V06', 'V07', 'V08') |
        ForEach-Object { $module -match "'$_'" } | Where-Object { -not $_ } | Measure-Object |
        Select-Object -ExpandProperty Count | ForEach-Object { $_ -eq 0 }
)
ok 'missing terraform fails closed' ($module -match 'terraform was not found on PATH')
ok 'strict mode fails on missing optional tools' ($module -match 'a missing optional tool is a failure, not a skip')
ok 'inventory gate is scaffold-independent' ($module -notmatch 'LZFactory\.Scaffold')
ok 'configuration_aliases validate is an explicit recorded skip' (
    $module -match 'configuration_aliases' -and
    $module -match 'standalone terraform validate is impossible upstream'
)
ok 'tool gates run against an isolated scratch copy' (
    $module -match 'GetTempPath' -and $module -match 'byte-identical'
)
ok 'evidence report and per-gate logs are emitted' (
    $module -match 'validate-report\.json' -and $module -match "'\.log'"
)
ok 'overall failure throws naming the failing gates' ($module -match 'Validation failed: gate')
ok 'scaffold apply requires the validation report' (
    $scaffoldModule -match 'ValidationReportPath' -and
    $scaffoldModule -match 'Run \./validate-render\.ps1' -and
    $scaffoldEntry -match 'ValidationReportPath'
)
ok 'stale validation evidence is rejected' ($scaffoldModule -match "'stale'")
ok 'validation override env is explicit and recorded' (
    $scaffoldModule -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED' -and
    $scaffoldModule -match 'overridden'
)
ok 'wrapper sequences the validate phase' (
    $wrapper -match "'validate'" -and
    $wrapper -match 'Invoke-EngagementValidate'
)
ok 'user checklist documents validation variables' (
    $checklist -match 'LZ_VALIDATE_EVIDENCE' -and
    $checklist -match 'LZ_VALIDATE_STRICT' -and
    $checklist -match 'LZ_VALIDATE_SKIP_SECURITY_SCAN' -and
    $checklist -match 'LZ_VALIDATE_SKIP_LINT' -and
    $checklist -match 'LZ_SCAFFOLD_ALLOW_UNVALIDATED'
)
ok 'gitignore covers the validation evidence directory' ($gitignore -match '/validate-evidence/')

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
