#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The renderer owns layer derivation (Get-LzActiveLayers). The broker consumes
# it rather than keeping a divergent copy — a bootstrap plan that provisions
# identities for layers the renderer never emits (or misses one it does) is a
# broken landing zone.
Import-Module (Join-Path $PSScriptRoot '../renderer/LZFactory.Renderer.psd1') -Force -ErrorAction Stop

function Write-LzBrokerEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

function Get-LzConfigValue {
    param([object]$Object, [string]$Name, $Default = $null)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Invoke-LzNativeJson {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowEmpty,
        [switch]$AllowFailure
    )
    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "$Command failed: $($output -join ' ')"
    }
    $text = ($output -join "`n").Trim()
    if (-not $text -and $AllowEmpty) { return $null }
    if (-not $text) { return $null }
    return $text | ConvertFrom-Json -Depth 50
}

function Assert-LzBrokerPrerequisites {
    param([object]$Config)
    foreach ($tool in @('az', 'gh')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool '$tool' is unavailable. Complete docs/USER-CHECKLIST.md and re-run."
        }
    }
    & az account show --output none 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI is not authenticated.' }
    & gh auth status 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated.' }
    if ($Config.backend.type -eq 'hcp-terraform' -and -not $env:TFE_TOKEN) {
        Write-LzBrokerEvent WARN 'TFE_TOKEN is absent; HCP workspace reconciliation will be recorded as pending.'
    }
}

function Get-LzEnvironmentSubscription {
    <#
    .SYNOPSIS
        Resolve the Azure subscription anchoring a GitHub environment.
    .DESCRIPTION
        Covers every environment name the schema can emit —
        unique(environments.platform ∪ environments.application):
        bootstrap, identity, connectivity, management, shared-services,
        sandbox, dev, test, uat, prod. Optional planes fall back to the
        management subscription; anything else fails closed.

        'bootstrap' resolution rule: the bootstrap environment's RBAC lives at
        the MG root (Get-LzEnvironmentScope — MG-scope work is not
        subscription-bound), but its AZURE_SUBSCRIPTION_ID still needs a value:
        the global layer maps to this environment (Get-LzLayerEnvironment) and
        its azurerm provider requires a subscription context even for
        MG-scope resources — and that provider is pinned to the management
        subscription (factory/templates/terraform/live/global/main.tf:
        subscription_id = var.management_subscription_id). The management
        subscription is therefore the anchor, matching what the rendered
        layer will actually run against.
    #>
    param([object]$Config, [string]$Environment)
    $subscriptions = $Config.azure.subscriptions
    switch ($Environment) {
        'bootstrap' { return $subscriptions.management }
        'connectivity' { return $subscriptions.connectivity }
        'management' { return $subscriptions.management }
        'identity' { return (Get-LzConfigValue $subscriptions 'identity' $subscriptions.management) }
        'shared-services' { return (Get-LzConfigValue $subscriptions 'sharedServices' $subscriptions.management) }
        'prod' { return $subscriptions.workloadProd }
        'sandbox' { return (Get-LzConfigValue $subscriptions 'sandbox' $subscriptions.management) }
        { $_ -in @('dev', 'test', 'uat') } {
            return (Get-LzConfigValue $subscriptions 'workloadNonProd' $subscriptions.management)
        }
        default {
            # Fail closed: silently mapping an unrecognised environment to a
            # subscription would grant an OIDC identity scope nobody reviewed.
            throw "Unknown environment '$Environment'. Expected one of: bootstrap, connectivity, management, identity, shared-services, prod, sandbox, dev, test, uat."
        }
    }
}

function Get-LzEnvironmentScope {
    param([object]$Config, [string]$Environment)
    if ($Environment -eq 'bootstrap') {
        return "/providers/Microsoft.Management/managementGroups/$($Config.azure.managementGroups.rootId)"
    }
    return "/subscriptions/$(Get-LzEnvironmentSubscription -Config $Config -Environment $Environment)"
}

function Get-LzCicdIdentityModel {
    # identity.cicdIdentityModel is broker-only: it never reaches a Terraform
    # variable (deliberately absent from factory/renderer/variable-map.json,
    # same pattern as the github.* keys). Absent key = 'minimal'.
    param([object]$Config)
    $identityConfig = Get-LzConfigValue $Config 'identity'
    if (-not $identityConfig) { return 'minimal' }
    return (Get-LzConfigValue $identityConfig 'cicdIdentityModel' 'minimal')
}

function Get-LzStateStorageScope {
    # Deterministic resource ID of the azurerm state storage account, so the
    # data-plane grants appear in the plan record before the account exists.
    param([object]$Config)
    if ($Config.backend.type -ne 'azurerm') { return $null }
    $backend = $Config.backend.azurerm
    $subscription = Get-LzConfigValue $backend 'subscriptionId' $Config.azure.subscriptions.management
    return "/subscriptions/$subscription/resourceGroups/$($backend.resourceGroupName)/providers/Microsoft.Storage/storageAccounts/$($backend.storageAccountName)"
}

function Get-LzSandboxRbacAssignment {
    <#
    .SYNOPSIS
        Constrained RBAC Administrator grant for the sandbox-cleanup automation.
    .DESCRIPTION
        The generated platform-management layer renders
        azurerm_role_assignment.sandbox_cleanup whenever
        azure.subscriptions.sandbox is set: it grants the automation account's
        managed identity Contributor on the sandbox subscription. Writing that
        assignment needs Microsoft.Authorization/roleAssignments/write there,
        which plain Contributor does not carry — without this grant the first
        platform-management apply fails AuthorizationFailed.

        The grant is Role Based Access Control Administrator scoped to the
        sandbox subscription ONLY, constrained by an ABAC delegation condition:
        the identity may only write/delete role assignments for the Contributor
        role and only to service principals. Never Owner/UAA, never
        unconditioned, never in the management subscription. Expressions
        mirror scripts/Start-LandingZoneBootstrap.ps1 (the proven originals);
        the attribute source differs per action — Request for
        roleAssignments/write, Resource for roleAssignments/delete
        (Microsoft Learn: delegate-role-assignments-examples).
    .OUTPUTS
        A role-assignment spec (role, scope, condition, conditionVersion), or
        $null when azure.subscriptions.sandbox is not set.
    #>
    param([object]$Config)
    $sandboxSubscription = Get-LzConfigValue $Config.azure.subscriptions 'sandbox'
    if ([string]::IsNullOrWhiteSpace([string]$sandboxSubscription)) { return $null }
    $contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'  # Contributor built-in role
    $condition = (
        "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
        "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
        "@Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})) AND " +
        "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
        "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
        "@Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}))"
    )
    return [pscustomobject]@{
        role = 'Role Based Access Control Administrator'
        scope = "/subscriptions/$sandboxSubscription"
        condition = $condition
        conditionVersion = '2.0'
    }
}

function New-LzBootstrapPlan {
    param([object]$Config)
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $environments = @($Config.environments.platform) + @($Config.environments.application) |
        Select-Object -Unique
    $identityModel = Get-LzCicdIdentityModel -Config $Config

    # State data-plane roles. The generated backend.tf.tmpl sets
    # use_azuread_auth and the state account disables shared keys (contract #3),
    # so without these grants a generated repo cannot read its own state.
    # hcp-terraform configs have no state storage account and get none.
    $stateScope = Get-LzStateStorageScope -Config $Config
    $planStateRoles = @([pscustomobject]@{ role = 'Storage Blob Data Reader'; scope = $stateScope })
    $applyStateRoles = @([pscustomobject]@{ role = 'Storage Blob Data Contributor'; scope = $stateScope })

    # Constrained sandbox RBAC Administrator (see Get-LzSandboxRbacAssignment):
    # emitted only when azure.subscriptions.sandbox is set, on the identity
    # that applies platform-management — minimal: the shared apply;
    # per-environment: the management environment's apply identity.
    $sandboxRbac = Get-LzSandboxRbacAssignment -Config $Config

    $identities = @()
    if ($identityModel -eq 'per-environment') {
        # This branch is byte-for-byte the pre-cicdIdentityModel broker output
        # for non-azurerm backends (Test-Bootstrap.ps1 asserts parity against
        # fixtures/bootstrap-plan-per-environment.expected.json), so existing
        # generated estates re-run idempotently with zero drift. Do not reshape
        # these records. azurerm backends additionally carry
        # stateRoleAssignments (the state data-plane defect fix).
        foreach ($environment in $environments) {
            $scope = Get-LzEnvironmentScope -Config $Config -Environment $environment
            $prefix = $Config.organization.companyShortName
            $planRecord = [pscustomobject]@{
                environment = $environment
                kind = 'plan'
                displayName = "sp-$prefix-$environment-plan"
                subject = "repo:$repo`:pull_request"
                roles = @('Reader')
                scope = $scope
            }
            $applyRecord = [pscustomobject]@{
                environment = $environment
                kind = 'apply'
                displayName = "sp-$prefix-$environment-apply"
                subject = "repo:$repo`:environment:$environment"
                roles = if ($environment -eq 'bootstrap') {
                    @('Management Group Contributor', 'Resource Policy Contributor')
                } else { @('Contributor') }
                scope = $scope
            }
            if ($stateScope) {
                $planRecord | Add-Member -NotePropertyName stateRoleAssignments -NotePropertyValue @($planStateRoles)
                $applyRecord | Add-Member -NotePropertyName stateRoleAssignments -NotePropertyValue @($applyStateRoles)
            }
            $identities += $planRecord
            $identities += $applyRecord
        }
        if ($sandboxRbac) {
            # platform-management is applied by the management environment's
            # identity (Get-LzLayerEnvironment), so the constrained grant lands
            # there. Fixture parity is unaffected: the pre-change fixture sets
            # no sandbox subscription, and this optional property exists only
            # when one is set — a deliberate, documented delta from the
            # pre-change output for sandbox-enabled configs.
            $managementApply = @($identities | Where-Object { $_.kind -eq 'apply' -and $_.environment -eq 'management' }) | Select-Object -First 1
            if (-not $managementApply) {
                $managementApply = @($identities | Where-Object kind -eq 'apply') | Select-Object -First 1
            }
            $managementApply | Add-Member -NotePropertyName delegatedRoleAssignments -NotePropertyValue @($sandboxRbac)
        }
    }
    else {
        # Minimal model (the default): exactly ONE plan and ONE apply identity.
        # The apply record's subject is a LIST — one environment:<name> subject
        # per unique environment — and its RBAC is the union of the scopes the
        # per-environment model would grant, deduplicated by scope. The plan
        # identity gets Reader once at the MG root so a single assignment
        # inherits everywhere. Contract #2 holds: pull_request only ever on
        # the plan record.
        $prefix = $Config.organization.companyShortName
        $mgScope = "/providers/Microsoft.Management/managementGroups/$($Config.azure.managementGroups.rootId)"
        $applySubjects = @()
        $applyAssignments = @()
        $seenScopes = @()
        foreach ($environment in $environments) {
            $applySubjects += "repo:$repo`:environment:$environment"
            $scope = Get-LzEnvironmentScope -Config $Config -Environment $environment
            if ($environment -eq 'bootstrap') {
                foreach ($role in @('Management Group Contributor', 'Resource Policy Contributor')) {
                    $applyAssignments += [pscustomobject]@{ role = $role; scope = $scope }
                }
            }
            elseif ($scope -notin $seenScopes) {
                $seenScopes += $scope
                $applyAssignments += [pscustomobject]@{ role = 'Contributor'; scope = $scope }
            }
        }
        $planAssignments = @([pscustomobject]@{ role = 'Reader'; scope = $mgScope })
        if ($stateScope) {
            $planAssignments += $planStateRoles
            $applyAssignments += $applyStateRoles
        }
        if ($sandboxRbac) { $applyAssignments += $sandboxRbac }
        $identities += [pscustomobject]@{
            environment = 'shared'
            environments = @($environments)
            kind = 'plan'
            displayName = "sp-$prefix-plan"
            subject = "repo:$repo`:pull_request"
            roleAssignments = @($planAssignments)
        }
        $identities += [pscustomobject]@{
            environment = 'shared'
            environments = @($environments)
            kind = 'apply'
            displayName = "sp-$prefix-apply"
            subject = @($applySubjects)
            roleAssignments = @($applyAssignments)
        }
    }
    # Single source of truth: the renderer's layer derivation (control AR3).
    $layers = @(Get-LzActiveLayers -Config $Config)

    # Every GitHub environment is reconciled with deployment_branch_policy
    # protected_branches=true (never custom policies). Without it, a
    # workflow_dispatch from an arbitrary branch executes THAT branch's copy of
    # the workflow file — one with the trusted default-branch checkout,
    # allowlist, or destroy-refusal stripped — and reviewers approve a
    # normal-looking run. Recorded here so plan-first mode shows the policy
    # before anything mutates GitHub. Mirrors scripts/Start-LandingZoneBootstrap.ps1.
    $githubEnvironments = @(foreach ($environment in $environments) {
        [pscustomobject]@{
            name = $environment
            deploymentBranchPolicy = [pscustomobject]@{
                protectedBranches = $true
                customBranchPolicies = $false
            }
        }
    })

    $plan = [pscustomobject]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = 'plan'
        repository = $repo
        tenantId = $Config.azure.tenantId
        environments = @($environments)
        layers = @($layers)
        identities = @($identities)
        githubEnvironments = @($githubEnvironments)
        backend = $Config.backend.type
    }
    if ($identityModel -ne 'per-environment') {
        # Only in minimal mode: the per-environment plan must stay byte-for-byte
        # the pre-change output (idempotent re-runs of existing estates).
        $plan | Add-Member -NotePropertyName identityModel -NotePropertyValue $identityModel
    }
    return $plan
}

function Get-LzEntraApplication {
    param([string]$DisplayName)
    $items = Invoke-LzNativeJson az @('ad', 'app', 'list', '--display-name', $DisplayName, '--output', 'json')
    return @($items) | Select-Object -First 1
}

function Set-LzFederatedCredential {
    param([string]$AppId, [string]$Name, [string]$Subject)
    $issuer = 'https://token.actions.githubusercontent.com'
    $audience = 'api://AzureADTokenExchange'
    $existing = @(Invoke-LzNativeJson az @('ad', 'app', 'federated-credential', 'list', '--id', $AppId, '--output', 'json')) |
        Where-Object { $_.name -eq $Name } | Select-Object -First 1
    $payload = [ordered]@{
        name = $Name
        issuer = $issuer
        subject = $Subject
        audiences = @($audience)
        description = 'Managed by Landing Zone Factory Stage 9'
    }
    $temp = New-TemporaryFile
    try {
        $payload | ConvertTo-Json -Depth 10 | Set-Content $temp -Encoding utf8
        if (-not $existing) {
            Invoke-LzNativeJson az @('ad', 'app', 'federated-credential', 'create', '--id', $AppId, '--parameters', "@$temp", '--output', 'json') | Out-Null
        }
        elseif ($existing.subject -ne $Subject -or $existing.issuer -ne $issuer) {
            Invoke-LzNativeJson az @('ad', 'app', 'federated-credential', 'update', '--id', $AppId, '--federated-credential-id', $existing.id, '--parameters', "@$temp", '--output', 'json') | Out-Null
        }
    }
    finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    $verified = @(Invoke-LzNativeJson az @('ad', 'app', 'federated-credential', 'list', '--id', $AppId, '--output', 'json')) |
        Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $verified -or $verified.subject -ne $Subject -or $verified.issuer -ne $issuer) {
        throw "Federated credential read-back failed for $Name."
    }
    return $verified
}

function Set-LzRoleAssignment {
    # Condition/ConditionVersion carry an ABAC delegation condition (the
    # constrained sandbox RBAC Administrator grant); both are optional and
    # omitted for ordinary assignments.
    param([string]$PrincipalId, [string]$Role, [string]$Scope, [string]$Condition, [string]$ConditionVersion)
    $existing = Invoke-LzNativeJson az @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $Scope, '--role', $Role, '--output', 'json'
    )
    if (@($existing).Count -eq 0) {
        $createArguments = @(
            'role', 'assignment', 'create', '--assignee-object-id', $PrincipalId,
            '--assignee-principal-type', 'ServicePrincipal', '--role', $Role,
            '--scope', $Scope, '--output', 'json'
        )
        if ($Condition) {
            $createArguments += @('--condition', $Condition, '--condition-version', $ConditionVersion)
        }
        Invoke-LzNativeJson az $createArguments | Out-Null
    }
    $verified = Invoke-LzNativeJson az @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $Scope, '--role', $Role, '--output', 'json'
    )
    if (@($verified).Count -eq 0) { throw "RBAC read-back failed for $Role at $Scope." }
    return @($verified)[0]
}

function Get-LzIdentityRecord {
    <#
    .SYNOPSIS
        Resolve the identity record serving an environment, in either model.
    .DESCRIPTION
        per-environment records carry environment = '<name>'; minimal-model
        records carry environment = 'shared' and serve every environment. An
        exact environment match wins so mixed audits stay unambiguous.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Identities,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter(Mandatory)][string]$Kind
    )
    $exact = @($Identities | Where-Object { $_.kind -eq $Kind -and $_.environment -eq $Environment }) | Select-Object -First 1
    if ($exact) { return $exact }
    return @($Identities | Where-Object { $_.kind -eq $Kind -and $_.environment -eq 'shared' }) | Select-Object -First 1
}

function Set-LzIdentity {
    param([object]$Identity)
    $app = Get-LzEntraApplication -DisplayName $Identity.displayName
    if (-not $app) {
        $app = Invoke-LzNativeJson az @('ad', 'app', 'create', '--display-name', $Identity.displayName, '--output', 'json')
    }
    $sp = Invoke-LzNativeJson az @('ad', 'sp', 'show', '--id', $app.appId, '--output', 'json') -AllowEmpty -AllowFailure
    if (-not $sp) {
        $sp = Invoke-LzNativeJson az @('ad', 'sp', 'create', '--id', $app.appId, '--output', 'json')
    }
    # One federated credential per subject. A minimal-model apply record has a
    # subject LIST (one environment:<name> per environment); every other record
    # has a single subject. The name stays github-<kind>-<environment> in both
    # models, so a per-environment estate re-run reconciles the exact
    # credentials it already has (zero drift).
    $credentials = @()
    foreach ($subject in @($Identity.subject)) {
        $credentialName = if ($subject -match ':environment:(?<environmentName>[^:]+)$') {
            "github-$($Identity.kind)-$($Matches['environmentName'])"
        }
        else {
            "github-$($Identity.kind)-$($Identity.environment)"
        }
        $credentials += Set-LzFederatedCredential -AppId $app.appId -Name $credentialName -Subject $subject
    }
    # Role assignments: minimal-model records carry explicit
    # roleAssignments (role+scope pairs, union across environments);
    # per-environment records carry roles at one scope plus optional
    # stateRoleAssignments (azurerm state data-plane grants) and
    # delegatedRoleAssignments (the constrained sandbox RBAC grant).
    $assignmentSpecs = @()
    if ($Identity.PSObject.Properties['roleAssignments']) {
        $assignmentSpecs += @($Identity.roleAssignments)
    }
    else {
        foreach ($role in @($Identity.roles)) {
            $assignmentSpecs += [pscustomobject]@{ role = $role; scope = $Identity.scope }
        }
        foreach ($extra in @('stateRoleAssignments', 'delegatedRoleAssignments')) {
            if ($Identity.PSObject.Properties[$extra]) {
                $assignmentSpecs += @($Identity.$extra)
            }
        }
    }
    $assignments = @()
    foreach ($spec in $assignmentSpecs) {
        $roleParameters = @{ PrincipalId = $sp.id; Role = $spec.role; Scope = $spec.scope }
        if ($spec.PSObject.Properties['condition'] -and $spec.condition) {
            $roleParameters.Condition = $spec.condition
            $roleParameters.ConditionVersion = $spec.conditionVersion
        }
        $assignments += Set-LzRoleAssignment @roleParameters
    }
    [pscustomobject]@{
        environment = $Identity.environment
        kind = $Identity.kind
        appId = $app.appId
        objectId = $sp.id
        displayName = $Identity.displayName
        subject = $Identity.subject
        roleAssignments = @($assignmentSpecs)
        federatedCredentialIds = @($credentials | ForEach-Object { $_.id })
        roleAssignmentIds = @($assignments | ForEach-Object { $_.id })
    }
}

function Set-LzGitHubVariable {
    param([string]$Repository, [string]$Name, [string]$Value, [string]$Environment)
    $ghArguments = @('variable', 'set', $Name, '--repo', $Repository, '--body', $Value)
    if ($Environment) { $ghArguments += @('--env', $Environment) }
    & gh @ghArguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to set GitHub variable $Name." }
}

function Set-LzGitHubEnvironment {
    param([object]$Config, [string]$Environment, [object[]]$Identities)
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    # deployment_branch_policy protected_branches=true on EVERY environment:
    # workflow_dispatch runs the workflow file from the dispatched ref, so an
    # unrestricted environment lets a write-capable actor dispatch from a
    # branch whose workflow copy strips the trusted default-branch checkout,
    # allowlist, or destroy-refusal — and reviewers see a normal-looking run.
    # Restricting deployments to protected branches pins runs that can mint
    # this environment's OIDC token to workflow code that passed the branch
    # protection gate. Matches scripts/Start-LandingZoneBootstrap.ps1.
    $branchPolicy = [ordered]@{
        protected_branches = $true
        custom_branch_policies = $false
    }
    $environmentBody = [ordered]@{ deployment_branch_policy = $branchPolicy }
    $temp = New-TemporaryFile
    try {
        $environmentBody | ConvertTo-Json -Depth 10 | Set-Content $temp -Encoding utf8
        Invoke-LzNativeJson gh @(
            'api', '--method', 'PUT', "repos/$repo/environments/$Environment",
            '--input', $temp.FullName
        ) | Out-Null
    }
    finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    $plan = Get-LzIdentityRecord -Identities $Identities -Environment $Environment -Kind 'plan'
    $apply = Get-LzIdentityRecord -Identities $Identities -Environment $Environment -Kind 'apply'
    Set-LzGitHubVariable -Repository $repo -Environment $Environment -Name 'AZURE_PLAN_CLIENT_ID' -Value $plan.appId
    Set-LzGitHubVariable -Repository $repo -Environment $Environment -Name 'AZURE_APPLY_CLIENT_ID' -Value $apply.appId
    Set-LzGitHubVariable -Repository $repo -Environment $Environment -Name 'AZURE_TENANT_ID' -Value $Config.azure.tenantId
    Set-LzGitHubVariable -Repository $repo -Environment $Environment -Name 'AZURE_SUBSCRIPTION_ID' `
        -Value ((Get-LzEnvironmentSubscription -Config $Config -Environment $Environment))

    $approvals = Get-LzConfigValue $Config.environments 'approvals'
    $approval = if ($approvals) { Get-LzConfigValue $approvals $Environment } else { $null }
    if ($approval) {
        $reviewers = @()
        foreach ($reviewer in @(Get-LzConfigValue $approval 'requiredReviewers' @())) {
            if ($reviewer -match '^team:(.+)$') {
                $team = Invoke-LzNativeJson gh @('api', "orgs/$($Config.github.ownerName)/teams/$($Matches[1])")
                $reviewers += @{ type = 'Team'; id = $team.id }
            }
            else {
                $user = Invoke-LzNativeJson gh @('api', "users/$reviewer")
                $reviewers += @{ type = 'User'; id = $user.id }
            }
        }
        $protection = [ordered]@{
            wait_timer = [int](Get-LzConfigValue $approval 'waitTimerMinutes' 0)
            prevent_self_review = [bool](Get-LzConfigValue $approval 'preventSelfReview' $true)
            reviewers = $reviewers
            # PUT replaces the environment's protection config wholesale, so
            # the branch policy must ride along or this call would strip it.
            deployment_branch_policy = $branchPolicy
        }
        $temp = New-TemporaryFile
        try {
            $protection | ConvertTo-Json -Depth 15 | Set-Content $temp -Encoding utf8
            Invoke-LzNativeJson gh @(
                'api', '--method', 'PUT', "repos/$repo/environments/$Environment",
                '--input', $temp.FullName
            ) | Out-Null
        }
        finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    }
    $verified = Invoke-LzNativeJson gh @('api', "repos/$repo/environments/$Environment")
    if (-not $verified.name -or $verified.name -ne $Environment) {
        throw "GitHub environment read-back failed for $Environment."
    }
    # Fail closed on the branch policy too: an environment left without it
    # silently reopens the dispatch-from-arbitrary-branch hole.
    $verifiedPolicy = Get-LzConfigValue -Object $verified -Name 'deployment_branch_policy'
    if (-not $verifiedPolicy -or -not [bool](Get-LzConfigValue -Object $verifiedPolicy -Name 'protected_branches' -Default $false)) {
        throw "Deployment branch policy read-back failed for $Environment (protected_branches is not enforced)."
    }
    return [pscustomobject]@{
        name = $verified.name
        url = $verified.url
        protectionRules = @($verified.protection_rules).Count
        protectedBranchesOnly = $true
    }
}

function Set-LzBranchProtection {
    <#
    .SYNOPSIS
        Reconcile branch protection on the generated repository's default branch.
    .DESCRIPTION
        Requires status checks, pull-request review, and linear history, and
        blocks force pushes and deletions, per the config's github.branchProtection
        block.

        Default required status check: 'repository-scan' — the Security Scan job
        the generated corpus ships in .github/workflows/security-scan.yml. It is
        the only generated check that triggers on every pull request with no
        path filter, so it always reports and a merge can never wait forever on
        a check that will not run. The other generated checks are deliberately
        NOT defaulted:

          - 'policy' (policy-diff-guardrails.yml) and 'pinning'
            (action-pinning-policy.yml) are path-filtered; requiring them would
            hang docs-only pull requests on "Expected" checks that never report
            — the same failure mode as the old 'qlty check' default, which
            assumed a third-party integration a fresh customer repository does
            not have.
          - 'Plan (<layer>)' (terraform-plan.yml) and 'Validate (<layer>)'
            (terraform-fmt-validate.yml) are layer-matrix jobs whose check-run
            names vary per configuration, and are also path-filtered.
    .NOTES
        Override the default with the LZ_REQUIRED_STATUS_CHECKS environment
        variable: a comma-separated list of check-run names, e.g.

            LZ_REQUIRED_STATUS_CHECKS = 'repository-scan,policy,pinning'

        Each context must exactly match the check-run name GitHub reports: the
        job's `name:` when set, otherwise the job id. Only add path-filtered or
        matrix checks if every pull request in the engagement will trigger them.
    #>
    param([object]$Config)
    $bp = Get-LzConfigValue $Config.github 'branchProtection'
    if (-not $bp -or -not (Get-LzConfigValue $bp 'enabled' $true)) {
        return [pscustomobject]@{ enabled = $false }
    }
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $branch = Get-LzConfigValue $Config.github 'defaultBranch' 'main'
    $requiredChecks = if ($env:LZ_REQUIRED_STATUS_CHECKS) {
        @($env:LZ_REQUIRED_STATUS_CHECKS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else { @('repository-scan') }
    $body = [ordered]@{
        required_status_checks = @{
            strict = $true
            contexts = $requiredChecks
        }
        enforce_admins = [bool](Get-LzConfigValue $bp 'enforceAdmins' $false)
        required_pull_request_reviews = @{
            dismiss_stale_reviews = [bool](Get-LzConfigValue $bp 'dismissStaleReviews' $true)
            require_code_owner_reviews = [bool](Get-LzConfigValue $bp 'requireCodeOwnerReview' $true)
            required_approving_review_count = [int](Get-LzConfigValue $bp 'requiredApprovals' 1)
        }
        restrictions = $null
        required_linear_history = [bool](Get-LzConfigValue $bp 'requireLinearHistory' $true)
        allow_force_pushes = $false
        allow_deletions = $false
    }
    $temp = New-TemporaryFile
    try {
        $body | ConvertTo-Json -Depth 20 | Set-Content $temp -Encoding utf8
        Invoke-LzNativeJson gh @(
            'api', '--method', 'PUT',
            "repos/$repo/branches/$branch/protection",
            '--input', $temp.FullName
        ) | Out-Null
    }
    finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    $verified = Invoke-LzNativeJson gh @('api', "repos/$repo/branches/$branch/protection")
    return [pscustomobject]@{
        enabled = $true
        requiredChecks = @($verified.required_status_checks.contexts)
        enforceAdmins = [bool]$verified.enforce_admins.enabled
        requiredApprovals = [int]$verified.required_pull_request_reviews.required_approving_review_count
    }
}

function Set-LzAzurermBackend {
    param([object]$Config)
    $backend = $Config.backend.azurerm
    $subscription = Get-LzConfigValue $backend 'subscriptionId' $Config.azure.subscriptions.management
    & az account set --subscription $subscription
    if ($LASTEXITCODE -ne 0) { throw "Cannot select backend subscription $subscription." }
    & az group create --name $backend.resourceGroupName --location $Config.azure.primaryRegion --output none
    if ($LASTEXITCODE -ne 0) { throw 'Failed to reconcile backend resource group.' }
    # --allow-shared-key-access false: contract #3 (AAD-only state access). The
    # generated backend.hcl sets use_azuread_auth = true and the identities get
    # Storage Blob Data Reader/Contributor data-plane grants; shared keys stay off.
    & az storage account create --name $backend.storageAccountName --resource-group $backend.resourceGroupName `
        --location $Config.azure.primaryRegion --sku Standard_GRS --kind StorageV2 `
        --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --output none
    if ($LASTEXITCODE -ne 0) { throw 'Failed to reconcile backend storage account.' }
    & az storage container create --name (Get-LzConfigValue $backend 'containerName' 'tfstate') `
        --account-name $backend.storageAccountName --auth-mode login --output none
    if ($LASTEXITCODE -ne 0) { throw 'Failed to reconcile backend container.' }
    $account = Invoke-LzNativeJson az @(
        'storage', 'account', 'show', '--name', $backend.storageAccountName,
        '--resource-group', $backend.resourceGroupName, '--output', 'json'
    )
    $container = Invoke-LzNativeJson az @(
        'storage', 'container', 'show',
        '--name', (Get-LzConfigValue $backend 'containerName' 'tfstate'),
        '--account-name', $backend.storageAccountName, '--auth-mode', 'login',
        '--output', 'json'
    )
    return [pscustomobject]@{
        subscriptionId = $subscription
        resourceGroup = $backend.resourceGroupName
        storageAccountId = $account.id
        container = $container.name
    }
}

function Set-LzHcpBackend {
    param([object]$Config, [string[]]$Layers)
    if (-not $env:TFE_TOKEN) { return @('Set TFE_TOKEN and re-run broker apply for HCP workspace reconciliation.') }
    $headers = @{ Authorization = "Bearer $env:TFE_TOKEN"; 'Content-Type' = 'application/vnd.api+json' }
    $org = $Config.backend.hcpTerraform.organization
    $prefix = Get-LzConfigValue $Config.backend.hcpTerraform 'workspacePrefix' $Config.organization.companyShortName
    $workspaces = @()
    foreach ($layer in $Layers) {
        $name = "$prefix-$layer"
        $encoded = [uri]::EscapeDataString($name)
        try {
            $workspace = Invoke-RestMethod -Method Get -Uri "https://app.terraform.io/api/v2/organizations/$org/workspaces/$encoded" -Headers $headers
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
            $body = @{ data = @{ type = 'workspaces'; attributes = @{ name = $name; 'execution-mode' = (Get-LzConfigValue $Config.backend.hcpTerraform 'executionMode' 'remote') } } } | ConvertTo-Json -Depth 10
            $workspace = Invoke-RestMethod -Method Post -Uri "https://app.terraform.io/api/v2/organizations/$org/workspaces" -Headers $headers -Body $body
        }
        $workspaces += [pscustomobject]@{ name = $workspace.data.attributes.name; id = $workspace.data.id }
    }
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $env:TFE_TOKEN | & gh secret set TF_API_TOKEN --repo $repo
    if ($LASTEXITCODE -ne 0) { throw 'Failed to set TF_API_TOKEN GitHub secret.' }
    Set-LzGitHubVariable -Repository $repo -Name 'TF_CLOUD_ORGANIZATION' -Value $org
    Set-LzGitHubVariable -Repository $repo -Name 'TF_CLOUD_WORKSPACE_PREFIX' -Value $prefix
    return [pscustomobject]@{ pending = @(); workspaces = $workspaces }
}

function Get-LzLayerEnvironment {
    param([object]$Config, [string]$Layer)
    switch ($Layer) {
        'global' { return 'bootstrap' }
        'platform-connectivity' { return 'connectivity' }
        'platform-management' { return 'management' }
        'platform-identity' { return 'identity' }
        'workloads-prod' { return 'prod' }
        'sandbox' { return 'sandbox' }
        'workloads-nonprod' {
            return @($Config.environments.application | Where-Object { $_ -in @('dev', 'test', 'uat') })[0]
        }
        default { return @($Config.environments.platform)[0] }
    }
}

function Test-LzFirstApplyPreflight {
    <#
    .SYNOPSIS
        Pre-flight the three known first-apply traps and return findings.
    .DESCRIPTION
        These traps otherwise surface as raw Terraform/Azure errors long after
        the broker has finished:

        PF-A: management_ip_ranges in the connectivity tfvars is still the
              commented wizard placeholder. It must be operator-supplied before
              the first platform-connectivity plan; left alone the layer falls
              back to the wide-open '*' default.
        PF-B: log_analytics_workspace_id loop-back. The value is owned by the
              platform-management layer and can only be filled in AFTER that
              layer applies; an uncommented value still carrying the '<...>'
              placeholder text will fail the plan.
        PF-C: sandbox RBAC. A sandbox layer with no dedicated
              azure.subscriptions.sandbox falls back to the management
              subscription, so no role assignment lands on the real sandbox
              subscription and the first sandbox apply fails AuthorizationFailed.

        The commented placeholders themselves are deliberate (contract #4 in
        .claude/CROSS-DOMAIN-CONTRACTS.md): the wizard never collects operator
        network ranges, and the workspace ID crosses layer state. This function
        detects and explains; it never edits and never blocks the broker.
    .PARAMETER Config
        Parsed lz-config.json object.
    .PARAMETER ConfigPath
        Path the config was loaded from; the wizard-exported
        connectivity.auto.tfvars is looked for beside it.
    .PARAMETER Layers
        Active layers from the renderer's derivation (New-LzBootstrapPlan).
    .NOTES
        The connectivity tfvars is searched for, in order: the
        LZ_CONNECTIVITY_TFVARS environment variable, connectivity.auto.tfvars
        beside the config file, then the rendered staging tree
        (LZ_RENDERED_PATH, default ./rendered-output).
    #>
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Layers
    )
    $findings = @()

    if ($Layers -contains 'platform-connectivity') {
        $configDirectory = Split-Path -Parent (Resolve-Path $ConfigPath)
        $renderedRoot = if ($env:LZ_RENDERED_PATH) { $env:LZ_RENDERED_PATH } else { './rendered-output' }
        $candidates = @(
            $env:LZ_CONNECTIVITY_TFVARS
            (Join-Path $configDirectory 'connectivity.auto.tfvars')
            (Join-Path $renderedRoot 'terraform/live/platform-connectivity/connectivity.auto.tfvars')
        ) | Where-Object { $_ }
        $tfvarsPath = $candidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1

        if (-not $tfvarsPath) {
            $findings += [pscustomobject]@{
                id = 'PF-A0'
                severity = 'WARN'
                message = "Connectivity tfvars not found; management_ip_ranges cannot be pre-flighted. Searched: $($candidates -join '; ')."
                remediation = 'Place the wizard-exported connectivity.auto.tfvars beside lz-config.json (or set LZ_CONNECTIVITY_TFVARS), then re-run the broker.'
            }
        }
        else {
            $tfvars = Get-Content $tfvarsPath -Raw
            if ($tfvars -notmatch '(?m)^\s*management_ip_ranges\s*=') {
                $findings += [pscustomobject]@{
                    id = 'PF-A1'
                    severity = 'WARN'
                    message = "management_ip_ranges is still the commented placeholder in $tfvarsPath. The first platform-connectivity plan will otherwise use the wide-open '*' default."
                    remediation = "Uncomment and set operator CIDR ranges, e.g. management_ip_ranges = [`"203.0.113.0/24`"]. '*' and '0.0.0.0/0' are rejected. The commented placeholder is deliberate (contract #4); fill it, do not restructure it."
                }
            }
            elseif ($tfvars -match '(?m)^\s*management_ip_ranges\s*=\s*(\[\s*)?"(\*|0\.0\.0\.0/0)"') {
                $findings += [pscustomobject]@{
                    id = 'PF-A2'
                    severity = 'WARN'
                    message = "management_ip_ranges in $tfvarsPath is set to a wildcard, exposing firewall management interfaces to every source address."
                    remediation = 'Replace the wildcard with the operator CIDR ranges before the first connectivity apply.'
                }
            }
            if ($tfvars -match '(?m)^\s*log_analytics_workspace_id\s*=\s*"?<') {
                $findings += [pscustomobject]@{
                    id = 'PF-B1'
                    severity = 'WARN'
                    message = "log_analytics_workspace_id in $tfvarsPath is uncommented but still carries the '<...>' placeholder text; the connectivity plan will fail on it."
                    remediation = 'Re-comment the line until platform-management has applied, then paste that layer''s log_analytics_workspace_id output.'
                }
            }
            elseif ($tfvars -notmatch '(?m)^\s*log_analytics_workspace_id\s*=') {
                $findings += [pscustomobject]@{
                    id = 'PF-B2'
                    severity = 'INFO'
                    message = 'log_analytics_workspace_id is not set in the connectivity tfvars; hub firewall diagnostics and threat-intel alerts will not be created.'
                    remediation = 'Expected before first apply: the value only exists AFTER the platform-management layer applies. Loop back then and set it from that layer''s output.'
                }
            }
        }
    }

    if ($Layers -contains 'sandbox') {
        $sandboxSubscription = Get-LzConfigValue $Config.azure.subscriptions 'sandbox'
        if (-not $sandboxSubscription) {
            $findings += [pscustomobject]@{
                id = 'PF-C1'
                severity = 'WARN'
                message = 'The sandbox layer is active but azure.subscriptions.sandbox is not set; the identity serving the sandbox environment falls back to the management subscription, so no RBAC lands on the real sandbox subscription and the first sandbox apply fails AuthorizationFailed. The constrained sandbox RBAC Administrator grant (needed by platform-management''s sandbox-cleanup role assignment) is also only emitted when the subscription is set.'
                remediation = 'Set azure.subscriptions.sandbox in lz-config.json (re-export from the wizard) and re-run the idempotent broker — that emits both the Contributor scope and the constrained RBAC Administrator grant. Granting them manually also works.'
            }
        }
    }

    return @($findings)
}

function Invoke-LzBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$DiscoveryPath,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [switch]$Apply,
        [switch]$AllowNotReady
    )
    $config = Get-Content (Resolve-Path $ConfigPath) -Raw | ConvertFrom-Json -Depth 50
    $discovery = Get-Content (Resolve-Path $DiscoveryPath) -Raw | ConvertFrom-Json -Depth 50
    if ($discovery.readOnly -ne $true) { throw 'Discovery inventory does not assert readOnly=true.' }
    $failCount = [int](Get-LzConfigValue $discovery.readiness 'failCount' 0)
    if ($Apply -and $failCount -gt 0 -and -not $AllowNotReady) {
        throw "Discovery has $failCount blocking finding(s). Use -AllowNotReady only with an approved exception."
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $plan = New-LzBootstrapPlan -Config $config
    $plan.mode = if ($Apply) { 'apply' } else { 'plan' }
    $planPath = Join-Path $OutputDirectory 'bootstrap-plan.json'
    $plan | ConvertTo-Json -Depth 30 | Set-Content $planPath -Encoding utf8

    # First-apply pre-flight: loud and early, but advisory. These are operator
    # traps in OTHER stages (connectivity tfvars, sandbox RBAC); failing the
    # broker on them would block the reconciliation that is this stage's job.
    $preflight = @(Test-LzFirstApplyPreflight -Config $config -ConfigPath $ConfigPath -Layers $plan.layers)
    if ($preflight.Count -eq 0) {
        Write-LzBrokerEvent OK 'First-apply pre-flight: no findings.'
    }
    foreach ($finding in $preflight) {
        Write-LzBrokerEvent $finding.severity ('{0}: {1}' -f $finding.id, $finding.message)
        if ($finding.remediation) { Write-LzBrokerEvent INFO ('    -> ' + $finding.remediation) }
    }

    $audit = [ordered]@{
        schemaVersion = '1.0.0'
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = $plan.mode
        repository = $plan.repository
        discoveryFailCount = $failCount
        preflight = @($preflight)
        identities = @()
        environments = @()
        backend = @{ type = $config.backend.type; status = 'planned' }
        branchProtection = @{ status = 'planned' }
        pendingUserActivities = @()
        status = 'planned'
        error = $null
    }

    $auditPath = Join-Path $OutputDirectory 'bootstrap-audit.json'
    try {
        if ($Apply) {
            Assert-LzBrokerPrerequisites -Config $config
            if ($config.backend.type -eq 'azurerm') {
                # State storage is reconciled BEFORE the identities: the identity
                # records carry Storage Blob Data Reader/Contributor grants scoped
                # to the state storage account (the state data-plane fix), and a
                # role assignment on a scope that does not exist yet fails.
                $audit.backend.details = Set-LzAzurermBackend -Config $config
            }
            foreach ($identity in $plan.identities) {
                Write-LzBrokerEvent INFO "Reconciling $($identity.displayName)"
                $audit.identities += Set-LzIdentity -Identity $identity
            }
            foreach ($environment in $plan.environments) {
                $audit.environments += Set-LzGitHubEnvironment -Config $config -Environment $environment -Identities $audit.identities
            }
            $planClientIds = [ordered]@{}
            $subscriptionIds = [ordered]@{}
            foreach ($layer in $plan.layers) {
                $environment = Get-LzLayerEnvironment -Config $config -Layer $layer
                $identity = Get-LzIdentityRecord -Identities $audit.identities -Environment $environment -Kind 'plan'
                $planClientIds[$layer] = $identity.appId
                $subscriptionIds[$layer] = Get-LzEnvironmentSubscription -Config $config -Environment $environment
            }
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_PLAN_CLIENT_IDS' `
                -Value ($planClientIds | ConvertTo-Json -Compress)
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_SUBSCRIPTION_IDS' `
                -Value ($subscriptionIds | ConvertTo-Json -Compress)
            $bootstrapPlan = Get-LzIdentityRecord -Identities $audit.identities -Environment 'bootstrap' -Kind 'plan'
            if (-not $bootstrapPlan) {
                $bootstrapPlan = $audit.identities | Where-Object kind -eq 'plan' | Select-Object -First 1
            }
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_PLAN_CLIENT_ID' -Value $bootstrapPlan.appId
            # Both branches resolve to the management subscription for a
            # default export: 'shared' (minimal model) is not a real
            # environment name and anchors to management directly, and the
            # per-environment 'bootstrap' record now resolves via
            # Get-LzEnvironmentSubscription's bootstrap rule (also management —
            # see the rationale there).
            $bootstrapSubscription = if ($bootstrapPlan.environment -eq 'shared') {
                $config.azure.subscriptions.management
            } else {
                Get-LzEnvironmentSubscription -Config $config -Environment $bootstrapPlan.environment
            }
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_SUBSCRIPTION_ID' -Value $bootstrapSubscription
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_TENANT_ID' -Value $config.azure.tenantId
            Set-LzGitHubVariable -Repository $plan.repository -Name 'FACTORY_VERSION' -Value $config.factoryVersion
            $audit.branchProtection = Set-LzBranchProtection -Config $config
            # azurerm state storage was already reconciled before the identities
            # (see above); only the HCP backend remains to reconcile here.
            if ($config.backend.type -ne 'azurerm') {
                if ($env:TFE_TOKEN) {
                    $hcp = Set-LzHcpBackend -Config $config -Layers $plan.layers
                    $audit.backend.details = $hcp
                    $audit.pendingUserActivities += @($hcp.pending)
                }
                else {
                    $audit.pendingUserActivities += 'Set TFE_TOKEN and re-run broker apply for HCP workspace reconciliation.'
                }
            }
            $audit.backend.status = if ($audit.pendingUserActivities.Count) { 'pending-user-activity' } else { 'reconciled' }
            $audit.status = if ($audit.pendingUserActivities.Count) { 'completed-with-user-activities' } else { 'completed' }
        }
    }
    catch {
        # The audit trail must record a failed apply, not vanish with it. The
        # finally block below still writes the file; this records why.
        $audit.status = 'failed'
        $audit.error = $_.Exception.Message
        $audit.pendingUserActivities += 'Resolve the recorded error and re-run the idempotent broker.'
        throw
    }
    finally {
        $audit.completedAt = (Get-Date).ToUniversalTime().ToString('o')
        $audit | ConvertTo-Json -Depth 40 | Set-Content $auditPath -Encoding utf8
        Write-LzBrokerEvent OK "Plan: $planPath"
        Write-LzBrokerEvent OK "Audit: $auditPath"
    }
    return [pscustomobject]@{ PlanPath = $planPath; AuditPath = $auditPath; Applied = [bool]$Apply }
}

Export-ModuleMember -Function Invoke-LzBootstrap, New-LzBootstrapPlan, Test-LzFirstApplyPreflight
