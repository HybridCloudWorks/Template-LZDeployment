#Requires -Version 7.0
# Stage 12 Factory CI static contract. Authored with Stage 12; execution was
# explicitly skipped in the implementation environment.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$workflow = Get-Content (Join-Path $repo '.github/workflows/factory-ci.yml') -Raw
$runner = Get-Content (Join-Path $repo 'factory/ci/Invoke-FactoryCI.ps1') -Raw
$network = Get-Content (Join-Path $repo 'factory/ci/Test-SiteNoNetwork.ps1') -Raw
$pins = Get-Content (Join-Path $repo 'factory/ci/Test-ActionPins.ps1') -Raw
$checklist = Get-Content (Join-Path $repo 'USER-CHECKLIST.md') -Raw
$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "  PASS $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

Write-Host "`n== Stage 12 Factory CI static contract ==" -ForegroundColor Cyan
ok 'workflow is credential-free' ($workflow -notmatch 'id-token:\s*write|azure/login|TFE_TOKEN')
ok 'workflow permissions are read-only' ($workflow -match 'permissions:\s*\r?\n\s*contents:\s*read')
ok 'workflow actions are SHA pinned' ($workflow -notmatch 'uses:\s*[^\s]+@(v\d+|main|master|latest)')
ok 'runner includes all test suites' (
    @('Test-Discovery','Test-Renderer','Test-Bootstrap','Test-Scaffold','Test-Import','Test-CI','Test-Dogfood') |
        ForEach-Object { $runner -match $_ } | Where-Object { -not $_ } | Measure-Object |
        Select-Object -ExpandProperty Count | ForEach-Object { $_ -eq 0 }
)
ok 'runner includes drift check' ($runner -match 'Test-LzSchemaDrift')
ok 'runner includes Terraform format and validate' ($runner -match "terraform @\('fmt'" -and $runner -match "terraform @\('validate'")
ok 'runner emits machine report' ($runner -match 'factory-ci-report\.json')
ok 'runner records no external mutation' ($runner -match 'externalMutation = \$false')
ok 'site policy denies network primitives' ($network -match 'fetch' -and $network -match 'XMLHttpRequest')
ok 'pinning policy requires forty hex characters' ($pins -match '\{40\}')
ok 'operator checklist names required status' ($checklist -match 'Factory CI')

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
