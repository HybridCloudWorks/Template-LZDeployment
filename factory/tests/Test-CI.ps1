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
$checklist = Get-Content (Join-Path $repo 'docs/USER-CHECKLIST.md') -Raw
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
    @('Test-Discovery','Test-Renderer','Test-Bootstrap','Test-Scaffold','Test-Validate','Test-CI','Test-Release') |
        ForEach-Object { $runner -match $_ } | Where-Object { -not $_ } | Measure-Object |
        Select-Object -ExpandProperty Count | ForEach-Object { $_ -eq 0 }
)
ok 'runner includes drift check' ($runner -match 'Test-LzSchemaDrift')
ok 'runner includes resource-provider coverage check' ($runner -match 'Test-ResourceProviderCoverage')
ok 'runner includes Terraform format and validate' ($runner -match "terraform @\('fmt'" -and $runner -match "terraform @\('validate'")
ok 'runner emits machine report' ($runner -match 'factory-ci-report\.json')
ok 'runner records no external mutation' ($runner -match 'externalMutation = \$false')
ok 'site policy denies network primitives' ($network -match 'fetch' -and $network -match 'XMLHttpRequest')
ok 'pinning policy requires forty hex characters' ($pins -match '\{40\}')
ok 'operator checklist names required status' ($checklist -match 'Factory CI')
ok 'runner verifies the ALZ policy catalog' ($runner -match 'New-AlzPolicyCatalog\.ps1')
ok 'runner checks ALZ policy defaults' ($runner -match 'Test-AlzPolicyDefaults\.ps1')
ok 'runner checks schema answer coverage' ($runner -match 'Test-SchemaCoverage\.ps1')

Write-Host "`n== ALZ policy catalog generation ==" -ForegroundColor Cyan
# Driven from a tiny local stand-in so the transformation is tested without
# reaching the network. What matters is the shape: the library's architecture
# definition is a FLAT list carrying parent_id, and reading it as a nested tree
# yields a plausible hierarchy in which everything is a child of the root.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$libFixture = Join-Path $PSScriptRoot 'fixtures/alzlib-min'
$catalogOut = Join-Path ([IO.Path]::GetTempPath()) "alz-catalog-$([guid]::NewGuid().ToString('n').Substring(0,8)).json"
try {
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'factory/ci/New-AlzPolicyCatalog.ps1') `
        -CatalogPath $catalogOut -LibraryRoot $libFixture | Out-Null
    $cat = Get-Content $catalogOut -Raw | ConvertFrom-Json -Depth 20

    $byId = @{}
    foreach ($mg in $cat.managementGroups) { $byId[$mg.id] = $mg }
    ok 'parent_id edges are preserved, not flattened' ($byId['child'].parent -eq 'root' -and $byId['leaf'].parent -eq 'child')
    ok 'the tenant-root parent is empty, not null text' ($byId['root'].parent -eq '')
    ok 'display names are carried' ($byId['leaf'].displayName -eq 'Leaf')

    ok 'assignments are deduplicated across archetypes' (@($cat.assignments.PSObject.Properties.Name).Count -eq 3)
    $ddos = $cat.assignments.'Enable-DDoS-VNET'
    ok 'an assignment records every archetype carrying it' (@($ddos.archetypes).Count -eq 2)
    ok 'archetypes resolve to management groups' ((@($ddos.managementGroups) -join ',') -eq 'child,root')
    # A one-element list must serialize as a list. PowerShell unwraps single-item
    # arrays returned from an if-expression, which silently turns a list of
    # required values into a bare string the wizard cannot iterate.
    ok 'single-element requirements stay arrays' ($ddos.requiredDefaults -is [array] -and @($ddos.requiredDefaults).Count -eq 1)

    $group = $cat.groups | Where-Object { $_.id -eq 'ddos' }
    ok 'a group inherits its members required values' (@($group.requiredDefaults) -contains 'ddos_protection_plan_id')
    ok 'an unmapped assignment is offered, not dropped' (@($cat.ungrouped) -contains 'Some-Unmapped-Policy')
    ok 'defaults record which parameter they fill' ($cat.defaults.'ddos_protection_plan_id'.consumedBy[0].parameters -contains 'ddosPlan')

    # Verify mode must actually detect drift, or the CI gate is decorative.
    $mutated = (Get-Content $catalogOut -Raw).Replace('"catalogVersion": "1.0.0"', '"catalogVersion": "9.9.9"')
    Set-Content $catalogOut $mutated -Encoding utf8
    & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'factory/ci/New-AlzPolicyCatalog.ps1') `
        -CatalogPath $catalogOut -LibraryRoot $libFixture -Verify 2>&1 | Out-Null
    ok 'verify mode fails on a drifted catalog' ($LASTEXITCODE -ne 0)
}
finally {
    Remove-Item -Force $catalogOut -ErrorAction SilentlyContinue
}

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
