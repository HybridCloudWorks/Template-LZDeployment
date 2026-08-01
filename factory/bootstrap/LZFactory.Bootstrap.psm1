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
            throw "Required tool '$tool' is unavailable. Complete USER-CHECKLIST.md and re-run."
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
    param([object]$Config, [string]$Environment)
    $subscriptions = $Config.azure.subscriptions
    switch ($Environment) {
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
            throw "Unknown environment '$Environment'. Expected one of: connectivity, management, identity, shared-services, prod, sandbox, dev, test, uat."
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

function New-LzBootstrapPlan {
    param([object]$Config)
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $environments = @($Config.environments.platform) + @($Config.environments.application) |
        Select-Object -Unique
    $identities = @()
    foreach ($environment in $environments) {
        $scope = Get-LzEnvironmentScope -Config $Config -Environment $environment
        $prefix = $Config.organization.companyShortName
        $identities += [pscustomobject]@{
            environment = $environment
            kind = 'plan'
            displayName = "sp-$prefix-$environment-plan"
            subject = "repo:$repo`:pull_request"
            roles = @('Reader')
            scope = $scope
        }
        $identities += [pscustomobject]@{
            environment = $environment
            kind = 'apply'
            displayName = "sp-$prefix-$environment-apply"
            subject = "repo:$repo`:environment:$environment"
            roles = if ($environment -eq 'bootstrap') {
                @('Management Group Contributor', 'Resource Policy Contributor')
            } else { @('Contributor') }
            scope = $scope
        }
    }
    # Single source of truth: the renderer's layer derivation (control AR3).
    $layers = @(Get-LzActiveLayers -Config $Config)

    [pscustomobject]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = 'plan'
        repository = $repo
        tenantId = $Config.azure.tenantId
        environments = @($environments)
        layers = @($layers)
        identities = @($identities)
        backend = $Config.backend.type
    }
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
    param([string]$PrincipalId, [string]$Role, [string]$Scope)
    $existing = Invoke-LzNativeJson az @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $Scope, '--role', $Role, '--output', 'json'
    )
    if (@($existing).Count -eq 0) {
        Invoke-LzNativeJson az @(
            'role', 'assignment', 'create', '--assignee-object-id', $PrincipalId,
            '--assignee-principal-type', 'ServicePrincipal', '--role', $Role,
            '--scope', $Scope, '--output', 'json'
        ) | Out-Null
    }
    $verified = Invoke-LzNativeJson az @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $Scope, '--role', $Role, '--output', 'json'
    )
    if (@($verified).Count -eq 0) { throw "RBAC read-back failed for $Role at $Scope." }
    return @($verified)[0]
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
    $credentialName = "github-$($Identity.kind)-$($Identity.environment)"
    $credential = Set-LzFederatedCredential -AppId $app.appId -Name $credentialName -Subject $Identity.subject
    $assignments = @()
    foreach ($role in @($Identity.roles)) {
        $assignments += Set-LzRoleAssignment -PrincipalId $sp.id -Role $role -Scope $Identity.scope
    }
    [pscustomobject]@{
        environment = $Identity.environment
        kind = $Identity.kind
        appId = $app.appId
        objectId = $sp.id
        displayName = $Identity.displayName
        subject = $Identity.subject
        roles = @($Identity.roles)
        scope = $Identity.scope
        federatedCredentialId = $credential.id
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
    Invoke-LzNativeJson gh @('api', '--method', 'PUT', "repos/$repo/environments/$Environment") | Out-Null
    $plan = $Identities | Where-Object { $_.environment -eq $Environment -and $_.kind -eq 'plan' } | Select-Object -First 1
    $apply = $Identities | Where-Object { $_.environment -eq $Environment -and $_.kind -eq 'apply' } | Select-Object -First 1
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
    return [pscustomobject]@{
        name = $verified.name
        url = $verified.url
        protectionRules = @($verified.protection_rules).Count
    }
}

function Set-LzBranchProtection {
    param([object]$Config)
    $bp = Get-LzConfigValue $Config.github 'branchProtection'
    if (-not $bp -or -not (Get-LzConfigValue $bp 'enabled' $true)) {
        return [pscustomobject]@{ enabled = $false }
    }
    $repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $branch = Get-LzConfigValue $Config.github 'defaultBranch' 'main'
    $requiredChecks = if ($env:LZ_REQUIRED_STATUS_CHECKS) {
        @($env:LZ_REQUIRED_STATUS_CHECKS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else { @('qlty check') }
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
    & az storage account create --name $backend.storageAccountName --resource-group $backend.resourceGroupName `
        --location $Config.azure.primaryRegion --sku Standard_GRS --kind StorageV2 `
        --min-tls-version TLS1_2 --allow-blob-public-access false --output none
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

    $audit = [ordered]@{
        schemaVersion = '1.0.0'
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = $plan.mode
        repository = $plan.repository
        discoveryFailCount = $failCount
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
                $identity = $audit.identities |
                    Where-Object { $_.environment -eq $environment -and $_.kind -eq 'plan' } |
                    Select-Object -First 1
                $planClientIds[$layer] = $identity.appId
                $subscriptionIds[$layer] = Get-LzEnvironmentSubscription -Config $config -Environment $environment
            }
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_PLAN_CLIENT_IDS' `
                -Value ($planClientIds | ConvertTo-Json -Compress)
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_SUBSCRIPTION_IDS' `
                -Value ($subscriptionIds | ConvertTo-Json -Compress)
            $bootstrapPlan = $audit.identities |
                Where-Object { $_.environment -eq 'bootstrap' -and $_.kind -eq 'plan' } |
                Select-Object -First 1
            if (-not $bootstrapPlan) {
                $bootstrapPlan = $audit.identities | Where-Object kind -eq 'plan' | Select-Object -First 1
            }
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_PLAN_CLIENT_ID' -Value $bootstrapPlan.appId
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_SUBSCRIPTION_ID' `
                -Value ((Get-LzEnvironmentSubscription -Config $config -Environment $bootstrapPlan.environment))
            Set-LzGitHubVariable -Repository $plan.repository -Name 'AZURE_TENANT_ID' -Value $config.azure.tenantId
            Set-LzGitHubVariable -Repository $plan.repository -Name 'FACTORY_VERSION' -Value $config.factoryVersion
            $audit.branchProtection = Set-LzBranchProtection -Config $config
            if ($config.backend.type -eq 'azurerm') {
                $audit.backend.details = Set-LzAzurermBackend -Config $config
            }
            else {
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

Export-ModuleMember -Function Invoke-LzBootstrap, New-LzBootstrapPlan
