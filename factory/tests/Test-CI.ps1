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

Write-Host "`n== ALZ plan proof (TODO 6.1a) ==" -ForegroundColor Cyan
# The harness assembles a standalone module around data "alz_architecture" from
# the RENDERED output. Its two extraction helpers are where it can silently go
# wrong: a truncated block or an unsubstituted reference would still produce a
# module that plans, just not the one this estate rendered.
$planProof = Join-Path $repo 'factory/ci/Test-AlzArchitecturePlan.ps1'
ok 'the harness exists' (Test-Path $planProof)

$planWorkflow = Join-Path $repo '.github/workflows/alz-plan-proof.yml'
$planWorkflowText = Get-Content $planWorkflow -Raw
ok 'the plan-proof workflow is dispatch-only' (
    $planWorkflowText -match '(?m)^on:\s*$' -and
    $planWorkflowText -match '(?m)^\s{2}workflow_dispatch:' -and
    $planWorkflowText -notmatch '(?m)^\s{2}(push|pull_request):')
ok 'it runs behind a protected environment' ($planWorkflowText -match '(?m)^\s*environment:\s*alz-plan-proof')
# It reads built-in policy definitions and nothing else. A write permission
# here would contradict the Reader-only claim its own header makes.
ok 'it grants no repository write' ($planWorkflowText -notmatch '(?m)^\s*contents:\s*write')

# Load the helpers without executing the script body. Dot-sourcing would run
# the render and the plan; this takes the two functions only.
$planSource = Get-Content $planProof -Raw
foreach ($fn in @('Get-LzBalancedBlock', 'Convert-LzRemoteStateReference')) {
    $m = [regex]::Match($planSource, "(?s)function $fn \{.*?\n\}\n")
    if (-not $m.Success) { throw "Could not lift $fn out of Test-AlzArchitecturePlan.ps1 — the test's extraction pattern is stale." }
    . ([scriptblock]::Create($m.Value))
}
$planStandIns = [regex]::Match($planSource, '(?s)\$script:RemoteStateStandIns = (\[ordered\]@\{.*?\n\})').Groups[1].Value
$script:RemoteStateStandIns = & ([scriptblock]::Create($planStandIns))
ok 'the stand-in table lifts cleanly' ($script:RemoteStateStandIns.Count -eq 6)

# The reason brace counting replaced a regex: policy_default_values is full of
# nested jsonencode({ ... }), and a non-greedy match stops at the first one.
$nested = @'
  policy_default_values = {
    a = jsonencode({
      value = "one"
    })
    b = jsonencode({
      value = "two"
    })
  }
'@
$block = Get-LzBalancedBlock -Text $nested -OpenPattern '(?m)^\s*policy_default_values\s*=\s*\{'
ok 'a nested jsonencode does not end the block early' ($block -match 'two' -and $block.TrimEnd().EndsWith('}'))

# A brace inside a string or a comment must not close the block either.
$tricky = @'
  policy_default_values = {
    a = "a } brace in a string"
    # a } brace in a comment
    b = "done"
  }
'@
$trickyBlock = Get-LzBalancedBlock -Text $tricky -OpenPattern '(?m)^\s*policy_default_values\s*=\s*\{'
ok 'braces in strings and comments do not end the block' ($trickyBlock -match 'done')

# Substitution must be total. A surviving reference would make the plan fail on
# a missing data source, and the failure would read as a defect in the estate.
$substituted = Convert-LzRemoteStateReference -Text 'x = data.terraform_remote_state.management.outputs.log_analytics_workspace_id'
ok 'a known output is substituted with a literal' ($substituted -match '^x = "/subscriptions/' -and $substituted -notmatch 'terraform_remote_state')

# The important direction: a NEW remote-state read added to the global layer
# must fail loudly here rather than be quietly left in place.
$threwOnUnknown = $false
try { Convert-LzRemoteStateReference -Text 'y = data.terraform_remote_state.management.outputs.something_new' | Out-Null }
catch { $threwOnUnknown = $true }
ok 'an unknown management output throws rather than passing through' $threwOnUnknown

# Every stand-in the table claims to cover must actually be read by the layer,
# and every one the layer reads must be covered. Checked against the template
# rather than a render, so this holds without running the renderer.
$globalTemplate = Get-Content (Join-Path $repo 'factory/templates/terraform/live/global/main.tf.tmpl') -Raw
$layerOutputs = @([regex]::Matches($globalTemplate, 'data\.terraform_remote_state\.management\.outputs\.(?<n>[A-Za-z0-9_]+)') |
    ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
$covered = @($script:RemoteStateStandIns.Keys | Sort-Object)
ok 'the stand-ins match what the layer actually reads' (
    ($layerOutputs.Count -gt 0) -and (-not (Compare-Object $layerOutputs $covered))
) 

Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
