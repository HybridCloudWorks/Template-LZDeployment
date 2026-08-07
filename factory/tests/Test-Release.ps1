#Requires -Version 7.0
# Stage 14 release-readiness static contract. Authored but not executed in the
# implementation environment.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$workflow = Get-Content (Join-Path $repo '.github/workflows/release-readiness.yml') -Raw
$runner = Get-Content (Join-Path $repo 'factory/release/Invoke-ReleaseReadiness.ps1') -Raw
$schema = Get-Content (Join-Path $repo 'factory/release/release-attestation.schema.json') -Raw
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw
$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 14 release-readiness static contract ==" -ForegroundColor Cyan
ok 'workflow is manual only' ($workflow -match 'workflow_dispatch:' -and $workflow -notmatch 'pull_request:|push:')
ok 'workflow has no cloud identity permission' ($workflow -notmatch 'id-token:\s*write|azure/login')
ok 'workflow actions are SHA pinned' ($workflow -notmatch 'uses:\s*[^\s]+@(v\d+|main|master|latest)')
ok 'attestation pins both reports' ($schema -match 'factoryCiReportSha256' -and $schema -match 'dogfoodReportSha256')
ok 'runner checks full eligible apply' ($runner -match 'releaseGateEligible' -and $runner -match "requestedLayer.*all")
ok 'runner checks evidence freshness' ($runner -match 'LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS')
ok 'runner computes all five gates' (
    @('schemaVariableDriftCheckPasses','dogfoodInstanceAppliesGreen',
      'oidcTokenExchangeVerifiedLive','allEmittedModulesImplemented',
      'siteMakesZeroNetworkRequests') |
        ForEach-Object { $runner -match $_ } | Where-Object { -not $_ } |
        Measure-Object | Select-Object -ExpandProperty Count |
        ForEach-Object { $_ -eq 0 }
)
ok 'runner cannot mutate release contract' ($runner -notmatch 'Set-Content.*factory-version\.json')
ok 'runner emits proposal and report' ($runner -match 'release-readiness-report\.json' -and $runner -match 'release-gates\.proposed\.json')
ok 'operator checklist documents Stage 14' ($checklist -match 'Stage 14')

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
