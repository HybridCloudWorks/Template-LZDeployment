#Requires -Version 7.0
# Stage 9 broker contract tests. Added with Stage 9; execution was explicitly
# skipped in the implementation environment because required external binaries
# and authenticated services were not part of that environment.
#
# Covers both identity.cicdIdentityModel modes:
#   minimal (default)  - 2 identities total, subject list on apply, union RBAC
#   per-environment    - byte-for-byte the pre-change output (idempotent estates)
# plus the azurerm state data-plane grants and the hcp-terraform negative case.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module "$repo/factory/bootstrap/LZFactory.Bootstrap.psm1" -Force

$pass = 0; $fail = 0
function ok($name, $condition, $extra) {
    if ($condition) { $script:pass++; Write-Host "PASS $name" }
    else { $script:fail++; Write-Host "FAIL $name$(if ($extra) { ""  -> $extra"" })" }
}

$cfgRaw = Get-Content "$PSScriptRoot/fixtures/sample-config.json" -Raw
function Get-SampleConfig { $script:cfgRaw | ConvertFrom-Json -Depth 50 }
$schemaPath = "$repo/factory/schema/lz-config.schema.json"
$mgRootScope = '/providers/Microsoft.Management/managementGroups/mg-contoso'

# ---------------------------------------------------------------------------
# per-environment mode: the legacy contract, selected explicitly
# ---------------------------------------------------------------------------
$cfg = Get-SampleConfig
$cfg.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue 'per-environment'
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

# Byte parity: with an hcp-terraform backend, per-environment output must be
# byte-for-byte the pre-change broker output, so existing generated estates
# re-run idempotently with zero drift. The fixture was captured from the
# pre-change module with generatedAt normalized.
$plan.generatedAt = 'NORMALIZED'
$expected = Get-Content "$PSScriptRoot/fixtures/bootstrap-plan-per-environment.expected.json" -Raw
$actual = $plan | ConvertTo-Json -Depth 30
ok 'per-environment plan is byte-for-byte the pre-change output' ($actual -eq $expected) $(
    if ($actual -ne $expected) { 'diff at first mismatch index ' + (0..([Math]::Min($actual.Length, $expected.Length) - 1) | Where-Object { $actual[$_] -ne $expected[$_] } | Select-Object -First 1) }
)
ok 'per-environment plan carries no identityModel marker (shape parity)' (
    -not $plan.PSObject.Properties['identityModel']
)

# ---------------------------------------------------------------------------
# minimal mode: the default, key absent
# ---------------------------------------------------------------------------
$cfgMin = Get-SampleConfig
$planMin = New-LzBootstrapPlan -Config $cfgMin
$planRecord = @($planMin.identities | Where-Object kind -eq 'plan')
$applyRecord = @($planMin.identities | Where-Object kind -eq 'apply')

ok 'minimal is the default when the key is absent' ($planMin.identityModel -eq 'minimal')
ok 'minimal emits exactly 2 identity records' (@($planMin.identities).Count -eq 2) (@($planMin.identities).Count)
ok 'minimal emits one plan and one apply record' ($planRecord.Count -eq 1 -and $applyRecord.Count -eq 1)
ok 'minimal display names have no environment segment' (
    $planRecord[0].displayName -eq 'sp-chg-plan' -and $applyRecord[0].displayName -eq 'sp-chg-apply'
)
ok 'minimal plan subject is the single pull_request subject' (
    @($planRecord[0].subject).Count -eq 1 -and $planRecord[0].subject -match ':pull_request$'
)
ok 'minimal plan identity is Reader at the MG root' (
    @($planRecord[0].roleAssignments | Where-Object { $_.role -eq 'Reader' -and $_.scope -eq $mgRootScope }).Count -eq 1
)
$applySubjects = @($applyRecord[0].subject)
ok 'minimal apply subject is a list with one entry per unique environment' (
    $applySubjects.Count -eq @($planMin.environments).Count
) ($applySubjects -join '; ')
ok 'every minimal apply subject is an exact environment subject' (
    @($applySubjects | Where-Object { $_ -notmatch ':environment:[^*]+$' }).Count -eq 0
)
ok 'contract #2: no pull_request subject on the apply record' (
    @($applySubjects | Where-Object { $_ -match 'pull_request' }).Count -eq 0
)
ok 'minimal apply covers every environment subject' (
    @($planMin.environments | Where-Object { $applySubjects -notcontains "repo:$($planMin.repository):environment:$_" }).Count -eq 0
)
ok 'no wildcard subjects in minimal mode' (
    @($applySubjects + @($planRecord[0].subject) | Where-Object { $_ -match '\*' }).Count -eq 0
)

# Union RBAC: MG-root roles from the bootstrap entry plus Contributor once per
# distinct subscription. Fixture: management ...001, connectivity ...002,
# prod ...003 => 2 MG-root roles + 3 Contributor assignments = 5, no dupes.
$applyAssignments = @($applyRecord[0].roleAssignments)
ok 'minimal apply RBAC is the deduplicated union (5 assignments)' ($applyAssignments.Count -eq 5) ($applyAssignments | ConvertTo-Json -Compress)
ok 'minimal apply keeps both MG-root bootstrap roles' (
    @($applyAssignments | Where-Object { $_.scope -eq $mgRootScope -and $_.role -in @('Management Group Contributor', 'Resource Policy Contributor') }).Count -eq 2
)
ok 'minimal apply grants Contributor once per distinct subscription' (
    @($applyAssignments | Where-Object role -eq 'Contributor').Count -eq 3 -and
    (@($applyAssignments | Where-Object role -eq 'Contributor' | ForEach-Object scope | Sort-Object -Unique).Count -eq 3)
)
ok 'no duplicate role+scope pairs in the union' (
    @($applyAssignments | ForEach-Object { "$($_.role)|$($_.scope)" } | Sort-Object -Unique).Count -eq $applyAssignments.Count
)

# Explicit 'minimal' must equal the absent-key default.
$cfgExplicit = Get-SampleConfig
$cfgExplicit.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue 'minimal'
$planExplicit = New-LzBootstrapPlan -Config $cfgExplicit
$planMin.generatedAt = 'NORMALIZED'; $planExplicit.generatedAt = 'NORMALIZED'
ok 'explicit minimal equals absent-key default' (
    ($planExplicit | ConvertTo-Json -Depth 30) -eq ($planMin | ConvertTo-Json -Depth 30)
)

# ---------------------------------------------------------------------------
# hcp-terraform backend: NO state storage roles in either mode
# ---------------------------------------------------------------------------
ok 'hcp-terraform minimal plan emits no storage data-plane roles' (
    ($planMin | ConvertTo-Json -Depth 30) -notmatch 'Storage Blob Data'
)
ok 'hcp-terraform per-environment plan emits no storage data-plane roles' (
    $actual -notmatch 'Storage Blob Data'
)

# ---------------------------------------------------------------------------
# azurerm backend: state data-plane grants (defect fix - the broker previously
# granted no data-plane roles although backend.tf sets use_azuread_auth)
# ---------------------------------------------------------------------------
function ConvertTo-AzurermBackendConfig([object]$Config) {
    $Config.backend.type = 'azurerm'
    $Config.backend | Add-Member -NotePropertyName azurerm -NotePropertyValue ([pscustomobject]@{
        resourceGroupName = 'rg-chg-tfstate'
        storageAccountName = 'chgtfstate'
        containerName = 'tfstate'
        subscriptionId = 'aaaaaaaa-0000-0000-0000-000000000001'
        useAzureAdAuth = $true
    })
    return $Config
}
$stateScope = '/subscriptions/aaaaaaaa-0000-0000-0000-000000000001/resourceGroups/rg-chg-tfstate/providers/Microsoft.Storage/storageAccounts/chgtfstate'

$cfgAzMin = ConvertTo-AzurermBackendConfig (Get-SampleConfig)
$planAzMin = New-LzBootstrapPlan -Config $cfgAzMin
$azPlanRec = @($planAzMin.identities | Where-Object kind -eq 'plan')[0]
$azApplyRec = @($planAzMin.identities | Where-Object kind -eq 'apply')[0]
ok 'azurerm minimal: plan identity gets Storage Blob Data Reader on state' (
    @($azPlanRec.roleAssignments | Where-Object { $_.role -eq 'Storage Blob Data Reader' -and $_.scope -eq $stateScope }).Count -eq 1
)
ok 'azurerm minimal: apply identity gets Storage Blob Data Contributor on state' (
    @($azApplyRec.roleAssignments | Where-Object { $_.role -eq 'Storage Blob Data Contributor' -and $_.scope -eq $stateScope }).Count -eq 1
)
ok 'azurerm minimal: no Contributor-level state grant on the plan identity' (
    @($azPlanRec.roleAssignments | Where-Object { $_.scope -eq $stateScope -and $_.role -ne 'Storage Blob Data Reader' }).Count -eq 0
)

$cfgAzPer = ConvertTo-AzurermBackendConfig (Get-SampleConfig)
$cfgAzPer.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue 'per-environment'
$planAzPer = New-LzBootstrapPlan -Config $cfgAzPer
ok 'azurerm per-environment: every plan record carries the Reader state grant' (
    @($planAzPer.identities | Where-Object kind -eq 'plan' | Where-Object {
        @($_.stateRoleAssignments | Where-Object { $_.role -eq 'Storage Blob Data Reader' -and $_.scope -eq $stateScope }).Count -ne 1
    }).Count -eq 0
)
ok 'azurerm per-environment: every apply record carries the Contributor state grant' (
    @($planAzPer.identities | Where-Object kind -eq 'apply' | Where-Object {
        @($_.stateRoleAssignments | Where-Object { $_.role -eq 'Storage Blob Data Contributor' -and $_.scope -eq $stateScope }).Count -ne 1
    }).Count -eq 0
)
ok 'azurerm per-environment: control-plane records otherwise unchanged' (
    @($planAzPer.identities).Count -eq ($envCount * 2) -and
    @($planAzPer.identities | Where-Object { $_.kind -eq 'plan' -and @($_.roles) -notcontains 'Reader' }).Count -eq 0
)

# ---------------------------------------------------------------------------
# constrained sandbox RBAC Administrator grant. platform-management renders
# azurerm_role_assignment.sandbox_cleanup whenever azure.subscriptions.sandbox
# is set, and writing it needs Microsoft.Authorization/roleAssignments/write in
# the sandbox subscription. The grant must appear exactly when the sandbox
# subscription is set (both models), on the identity that applies
# platform-management, ABAC-constrained to Contributor-to-ServicePrincipal.
#
# Parity note: the per-environment parity fixture sets NO sandbox subscription
# (asserted below), so byte parity against the pre-change output holds. For
# sandbox-enabled per-environment configs the optional delegatedRoleAssignments
# property is a deliberate, documented delta from the pre-change output - the
# pre-change broker never created this grant, which is the defect being fixed.
# ---------------------------------------------------------------------------
$sandboxSub = 'aaaaaaaa-0000-0000-0000-000000000004'
$sandboxScope = "/subscriptions/$sandboxSub"
$contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
# Exact expressions mirrored from scripts/Start-LandingZoneBootstrap.ps1
# (attribute source differs per action: Request for write, Resource for delete).
$expectedCondition = (
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
    "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
    "@Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})) AND " +
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
    "@Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}))"
)
function Add-SandboxSubscription([object]$Config) {
    $Config.azure.subscriptions | Add-Member -NotePropertyName sandbox -NotePropertyValue $script:sandboxSub
    return $Config
}
function Test-SandboxGrant($spec) {
    $spec.role -eq 'Role Based Access Control Administrator' -and
    $spec.scope -eq $script:sandboxScope -and
    $spec.conditionVersion -eq '2.0' -and
    $spec.condition -eq $script:expectedCondition
}

# Negative space first: the parity premise and the never-otherwise rule.
$fixtureCfg = Get-SampleConfig
ok 'parity premise holds: fixture sets no sandbox subscription' (
    -not $fixtureCfg.azure.subscriptions.PSObject.Properties['sandbox']
)
ok 'no sandbox: minimal plan contains no RBAC Administrator grant' (
    ($planMin | ConvertTo-Json -Depth 30) -notmatch 'Role Based Access Control Administrator'
)
ok 'no sandbox: per-environment plan contains no RBAC Administrator grant' (
    $actual -notmatch 'Role Based Access Control Administrator' -and
    @($plan.identities | Where-Object { $_.PSObject.Properties['delegatedRoleAssignments'] }).Count -eq 0
)

# minimal + sandbox: the grant lands in the shared apply union, once.
$cfgSbxMin = Add-SandboxSubscription (Get-SampleConfig)
$planSbxMin = New-LzBootstrapPlan -Config $cfgSbxMin
$sbxApply = @($planSbxMin.identities | Where-Object kind -eq 'apply')[0]
$sbxPlan = @($planSbxMin.identities | Where-Object kind -eq 'plan')[0]
$sbxGrants = @($sbxApply.roleAssignments | Where-Object { $_.role -eq 'Role Based Access Control Administrator' })
ok 'sandbox minimal: exactly one RBAC Administrator grant on the shared apply' ($sbxGrants.Count -eq 1)
ok 'sandbox minimal: grant is sandbox-scoped with the exact ABAC condition' (
    $sbxGrants.Count -eq 1 -and (Test-SandboxGrant $sbxGrants[0])
) ($sbxGrants | ConvertTo-Json -Compress)
ok 'sandbox minimal: union is otherwise unchanged (5 + 1 assignments)' (
    @($sbxApply.roleAssignments).Count -eq 6
)
ok 'sandbox minimal: plan identity never carries the grant' (
    ($sbxPlan.roleAssignments | ConvertTo-Json -Depth 10) -notmatch 'Role Based Access Control Administrator'
)

# per-environment + sandbox: the grant lands on the management apply identity
# (the one that applies platform-management), and nowhere else.
$cfgSbxPer = Add-SandboxSubscription (Get-SampleConfig)
$cfgSbxPer.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue 'per-environment'
$planSbxPer = New-LzBootstrapPlan -Config $cfgSbxPer
$carriers = @($planSbxPer.identities | Where-Object { $_.PSObject.Properties['delegatedRoleAssignments'] })
ok 'sandbox per-environment: exactly one record carries the grant' ($carriers.Count -eq 1)
ok 'sandbox per-environment: the carrier is the management apply identity' (
    $carriers.Count -eq 1 -and $carriers[0].environment -eq 'management' -and $carriers[0].kind -eq 'apply'
)
ok 'sandbox per-environment: grant is sandbox-scoped with the exact ABAC condition' (
    $carriers.Count -eq 1 -and @($carriers[0].delegatedRoleAssignments).Count -eq 1 -and
    (Test-SandboxGrant @($carriers[0].delegatedRoleAssignments)[0])
)
ok 'sandbox per-environment: control-plane fields of the carrier are unchanged' (
    $carriers.Count -eq 1 -and
    @($carriers[0].roles) -contains 'Contributor' -and
    $carriers[0].scope -eq '/subscriptions/aaaaaaaa-0000-0000-0000-000000000001' -and
    $carriers[0].subject -eq 'repo:contoso-platform/contoso_LZ_Deployment:environment:management'
)
ok 'sandbox per-environment: no plan record carries any RBAC Administrator grant' (
    @($planSbxPer.identities | Where-Object { $_.kind -eq 'plan' -and (($_ | ConvertTo-Json -Depth 10) -match 'Role Based Access Control Administrator') }).Count -eq 0
)

# ---------------------------------------------------------------------------
# schema: identity.cicdIdentityModel accepts both enum values, rejects others,
# and the fixture without the key (the minimal default) stays valid
# ---------------------------------------------------------------------------
ok 'schema: fixture without the key validates' (Test-Json -Json $cfgRaw -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
foreach ($value in @('minimal', 'per-environment')) {
    $c = Get-SampleConfig
    $c.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue $value
    ok "schema: cicdIdentityModel '$value' validates" (
        Test-Json -Json ($c | ConvertTo-Json -Depth 50) -SchemaFile $schemaPath -ErrorAction SilentlyContinue
    )
}
$cBad = Get-SampleConfig
$cBad.identity | Add-Member -NotePropertyName cicdIdentityModel -NotePropertyValue 'per-subscription'
ok 'schema: an unknown cicdIdentityModel value is rejected' (
    -not (Test-Json -Json ($cBad | ConvertTo-Json -Depth 50) -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
)

Write-Host "$pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
