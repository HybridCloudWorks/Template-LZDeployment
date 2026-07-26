#Requires -Version 7.0
# Stage 9 broker contract tests. Added with Stage 9; execution was explicitly
# skipped in the implementation environment because required external binaries
# and authenticated services were not part of that environment.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$repo/factory/bootstrap/LZFactory.Bootstrap.psm1" -Force

$pass = 0; $fail = 0
function ok($name, $condition) {
    if ($condition) { $script:pass++; Write-Host "PASS $name" }
    else { $script:fail++; Write-Host "FAIL $name" }
}

$cfg = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw | ConvertFrom-Json -Depth 50
$plan = New-LzBootstrapPlan -Config $cfg
$envCount = @($cfg.environments.platform).Count + @($cfg.environments.application).Count

ok 'plan is non-mutating by default' ($plan.mode -eq 'plan')
ok 'two identities per environment' (@($plan.identities).Count -eq ($envCount * 2))
ok 'all plan identities are Reader' (
    @($plan.identities | Where-Object { $_.kind -eq 'plan' -and @($_.roles) -notcontains 'Reader' }).Count -eq 0
)
ok 'workload apply identities are Contributor' (
    @($plan.identities | Where-Object {
        $_.kind -eq 'apply' -and $_.environment -ne 'bootstrap' -and
        @($_.roles) -notcontains 'Contributor'
    }).Count -eq 0
)
ok 'bootstrap apply uses management-group policy roles' (
    @($plan.identities | Where-Object {
        $_.kind -eq 'apply' -and $_.environment -eq 'bootstrap' -and
        @($_.roles) -contains 'Management Group Contributor' -and
        @($_.roles) -contains 'Resource Policy Contributor'
    }).Count -eq 1
)
ok 'plan subjects are exact pull_request subjects' (
    @($plan.identities | Where-Object { $_.kind -eq 'plan' -and $_.subject -notmatch ':pull_request$' }).Count -eq 0
)
ok 'apply subjects are exact environment subjects' (
    @($plan.identities | Where-Object { $_.kind -eq 'apply' -and $_.subject -notmatch ':environment:[^*]+$' }).Count -eq 0
)
ok 'no wildcard subjects' (
    @($plan.identities | Where-Object { $_.subject -match '\*' }).Count -eq 0
)
ok 'repository derived from config' ($plan.repository -eq 'contoso-platform/contoso_LZ_Deployment')
ok 'active layers retained' ($plan.layers -contains 'platform-connectivity' -and $plan.layers -contains 'workloads-prod')

Write-Host "$pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
