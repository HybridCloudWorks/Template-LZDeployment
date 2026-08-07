#Requires -Version 7.0
# Stage 13 dogfood static contract. Authored with Stage 13; execution was
# explicitly skipped in the implementation environment.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$workflow = Get-Content (Join-Path $repo '.github/workflows/dogfood-instance.yml') -Raw
$runner = Get-Content (Join-Path $repo 'factory/dogfood/Invoke-Dogfood.ps1') -Raw
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw
$version = Get-Content (Join-Path $repo 'factory-version.json') -Raw | ConvertFrom-Json
$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 13 dogfood static contract ==" -ForegroundColor Cyan
ok 'workflow is manual only' ($workflow -match 'workflow_dispatch:' -and $workflow -notmatch 'pull_request:|push:')
ok 'workflow actions are SHA pinned' ($workflow -notmatch 'uses:\s*[^\s]+@(v\d+|main|master|latest)')
ok 'apply uses protected environment' ($workflow -match 'environment:\s*\$\{\{ inputs\.environment \}\}')
ok 'plan uses explicit read-only identity' ($workflow -match 'LZ_DOGFOOD_PLAN_CLIENT_ID')
ok 'apply requires explicit authorization' ($runner -match 'LZ_DOGFOOD_APPLY' -and $runner -match 'Apply refused')
ok 'runner renders before Terraform' ($runner.IndexOf('Invoke-LzRender') -lt $runner.IndexOf("'init'"))
ok 'runner refuses destructive changes' ($runner -match 'destructive change' -and $runner -match "contains 'delete'")
ok 'runner emits evidence' ($runner -match 'dogfood-report\.json')
ok 'release gate stays evidence-driven' (-not $version.releaseGates.dogfoodInstanceAppliesGreen)
ok 'operator checklist documents Stage 13' ($checklist -match 'Stage 13')

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
