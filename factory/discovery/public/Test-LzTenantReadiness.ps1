#Requires -Version 7.0
<#
    Tenant readiness validation.

    Answers ten capability questions with Pass / Warning / Fail, every one of
    them WITHOUT mutating anything. Capability is proven by reading the
    operator's effective permissions and directory role memberships, never by
    attempting a create and rolling it back — a rollback that fails halfway
    leaves debris in a tenant the operator may not own.

    Three-state semantics, and the distinction matters:

      Pass    — the capability is confirmed present.
      Warning — the capability could not be confirmed, or is present but with a
                caveat. Proceeding is a judgement call.
      Fail    — the capability is confirmed absent. Bootstrap will not succeed.

    An unreadable permission set produces Warning, never Pass. "I could not
    check" and "it is fine" must never render identically.
#>

Set-StrictMode -Version Latest

function New-LzReadinessCheck {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Warning', 'Fail')][string]$Status,
        [string]$Detail = '',
        [string]$Remediation = '',
        [string]$Category = 'General'
    )
    [pscustomobject]@{
        Id = $Id; Name = $Name; Status = $Status
        Detail = $Detail; Remediation = $Remediation; Category = $Category
    }
}

function Test-LzTenantReadiness {
    <#
    .SYNOPSIS
        Run the ten readiness checks against the discovered inventory.
    .PARAMETER Config
        The parsed lz-config.json object.
    .PARAMETER GitHubInventory
    .PARAMETER EntraInventory
    .PARAMETER AzureInventory
    .PARAMETER TerraformInventory
        Outputs from the corresponding Get-Lz*Inventory functions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [object]$GitHubInventory = $null,
        [object]$EntraInventory = $null,
        [object]$AzureInventory = $null,
        [object]$TerraformInventory = $null
    )

    Write-LzSection 'Tenant readiness validation'
    $checks = @()

    $checks += Test-LzCanCreateAppRegistrations -Entra $EntraInventory
    $checks += Test-LzCanCreateFederatedCredentials -Entra $EntraInventory
    $checks += Test-LzCanCreateManagementGroups -Config $Config -Azure $AzureInventory
    $checks += Test-LzCanCreateSubscriptions -Config $Config -Azure $AzureInventory
    $checks += Test-LzCanCreatePolicies -Config $Config
    $checks += Test-LzCanAssignRbac -Config $Config
    $checks += Test-LzCanConfigureDiagnostics -Config $Config
    $checks += Test-LzCanDeployNetworking -Config $Config -Azure $AzureInventory
    $checks += Test-LzGitHubAccess -Config $Config -GitHub $GitHubInventory
    $checks += Test-LzTerraformBackendAccess -Config $Config -Terraform $TerraformInventory

    foreach ($c in $checks) {
        switch ($c.Status) {
            'Pass'    { Write-LzOK   ("{0}: {1}" -f $c.Name, (Get-LzTerseMessage $c.Detail 160)) }
            'Warning' { Write-LzWarn ("{0}: {1}" -f $c.Name, (Get-LzTerseMessage $c.Detail 160)) }
            'Fail'    { Write-LzFail ("{0}: {1}" -f $c.Name, (Get-LzTerseMessage $c.Detail 160)) }
        }
    }

    $fails = @($checks | Where-Object { $_.Status -eq 'Fail' }).Count
    $warns = @($checks | Where-Object { $_.Status -eq 'Warning' }).Count

    [pscustomobject]@{
        Checks       = $checks
        PassCount    = @($checks | Where-Object { $_.Status -eq 'Pass' }).Count
        WarningCount = $warns
        FailCount    = $fails
        Ready        = ($fails -eq 0)
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Helpers
# ══════════════════════════════════════════════════════════════════════════════

function Get-LzScopePermissionState {
    <#
    .SYNOPSIS
        Test an ARM action at a scope, returning Pass / Warning / Fail.
    .DESCRIPTION
        Warning is returned when the permission set itself could not be read.
        That is deliberately distinct from Fail: not knowing is different from
        knowing the answer is no, and only the latter justifies stopping.
    #>
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Action
    )
    try {
        $permitted = Test-LzActionPermitted -Scope $Scope -Action $Action
        return @{ State = $(if ($permitted) { 'Pass' } else { 'Fail' }); Error = '' }
    }
    catch {
        return @{ State = 'Warning'; Error = (Protect-LzSecretText $_.Exception.Message) }
    }
}

function Get-LzManagementGroupScope {
    param([Parameter(Mandatory)][object]$Config)
    $root = $Config.azure.managementGroups.rootId
    return "/providers/Microsoft.Management/managementGroups/$root"
}

function Get-LzPrimarySubscriptionScope {
    param([Parameter(Mandatory)][object]$Config)
    return "/subscriptions/$($Config.azure.subscriptions.connectivity)"
}

# ══════════════════════════════════════════════════════════════════════════════
#  The ten checks
# ══════════════════════════════════════════════════════════════════════════════

function Test-LzCanCreateAppRegistrations {
    param([object]$Entra)

    if (-not $Entra) {
        return New-LzReadinessCheck -Id 'R01' -Category 'Identity' -Name 'Create app registrations' -Status 'Warning' `
            -Detail 'Entra discovery did not run.' -Remediation 'Re-run discovery with Entra probing enabled.'
    }

    $cap = $Entra.Capabilities

    if (-not $cap.RolesReadable) {
        return New-LzReadinessCheck -Id 'R01' -Category 'Identity' -Name 'Create app registrations' -Status 'Warning' `
            -Detail 'Directory role membership could not be read, so this capability is unconfirmed.' `
            -Remediation 'Grant the operator Directory Readers, or have an Entra administrator confirm they hold Application Administrator or Global Administrator.'
    }

    if ($cap.CanManageApplications) {
        return New-LzReadinessCheck -Id 'R01' -Category 'Identity' -Name 'Create app registrations' -Status 'Pass' `
            -Detail ("Holds {0}." -f (($cap.HeldDirectoryRoles | Where-Object { $_ -match 'Administrator' }) -join ', '))
    }

    # Tenants can permit all members to register applications, so absence of an
    # admin role is not automatically fatal.
    return New-LzReadinessCheck -Id 'R01' -Category 'Identity' -Name 'Create app registrations' -Status 'Warning' `
        -Detail 'No application-administrator directory role found. Some tenants still allow any member to register applications.' `
        -Remediation 'Assign Application Administrator (least privilege) or Cloud Application Administrator to the bootstrap operator. Global Administrator is not required.'
}

function Test-LzCanCreateFederatedCredentials {
    param([object]$Entra)

    if (-not $Entra) {
        return New-LzReadinessCheck -Id 'R02' -Category 'Identity' -Name 'Create federated credentials' -Status 'Warning' `
            -Detail 'Entra discovery did not run.'
    }

    $cap = $Entra.Capabilities

    if ($cap.AppsNearFederatedCredLimit.Count -gt 0) {
        $names = ($cap.AppsNearFederatedCredLimit | ForEach-Object { $_.AppId }) -join ', '
        return New-LzReadinessCheck -Id 'R02' -Category 'Identity' -Name 'Create federated credentials' -Status 'Warning' `
            -Detail "Application(s) $names are at or near the 20-credential-per-application ceiling." `
            -Remediation 'The factory creates one application per environment, which keeps counts low. Do not reuse an existing near-limit application.'
    }

    if ($cap.CanManageApplications) {
        return New-LzReadinessCheck -Id 'R02' -Category 'Identity' -Name 'Create federated credentials' -Status 'Pass' `
            -Detail 'Application-administrator role permits federated identity credential management.'
    }

    return New-LzReadinessCheck -Id 'R02' -Category 'Identity' -Name 'Create federated credentials' -Status 'Warning' `
        -Detail 'Unconfirmed — depends on the same role as app registration.' `
        -Remediation 'Resolve check R01 first; federated credentials require the same permission.'
}

function Test-LzCanCreateManagementGroups {
    param([object]$Config, [object]$Azure)

    if ($Config.deploymentStrategy.mode -eq 'brownfield' -and $Azure -and $Azure.Probes['Management groups'].Status -eq 'Ok') {
        # Brownfield may adopt an existing hierarchy rather than create one.
        $r = Get-LzScopePermissionState -Scope (Get-LzManagementGroupScope $Config) -Action 'Microsoft.Management/managementGroups/write'
        if ($r.State -eq 'Fail') {
            return New-LzReadinessCheck -Id 'R03' -Category 'Azure' -Name 'Create management groups' -Status 'Warning' `
                -Detail 'Cannot create management groups, but this is a brownfield deployment that may adopt the existing hierarchy.' `
                -Remediation 'Confirm the existing hierarchy matches the configured strategy, or grant Management Group Contributor at the root.'
        }
    }

    $scope = Get-LzManagementGroupScope $Config
    $r = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Management/managementGroups/write'

    switch ($r.State) {
        'Pass' {
            return New-LzReadinessCheck -Id 'R03' -Category 'Azure' -Name 'Create management groups' -Status 'Pass' `
                -Detail "Permitted at $scope."
        }
        'Warning' {
            return New-LzReadinessCheck -Id 'R03' -Category 'Azure' -Name 'Create management groups' -Status 'Warning' `
                -Detail "Effective permissions at $scope could not be read: $($r.Error)" `
                -Remediation 'Grant at least Reader at the root management group so readiness can be assessed.'
        }
        default {
            return New-LzReadinessCheck -Id 'R03' -Category 'Azure' -Name 'Create management groups' -Status 'Fail' `
                -Detail "Microsoft.Management/managementGroups/write is not permitted at $scope." `
                -Remediation 'Assign Management Group Contributor at the root management group. Alternatively, set azure.managementGroups.rootId to an existing intermediate management group you already control — see assumption A7 in docs/factory/FACTORY-DESIGN.md.'
        }
    }
}

function Test-LzCanCreateSubscriptions {
    param([object]$Config, [object]$Azure)

    # The factory does not create subscriptions; it consumes ones supplied in the
    # configuration. What matters is that each configured subscription exists and
    # is reachable.
    if (-not $Azure -or -not $Azure.Probes.Contains('Configured subscriptions')) {
        return New-LzReadinessCheck -Id 'R04' -Category 'Azure' -Name 'Subscription availability' -Status 'Warning' `
            -Detail 'Configured subscriptions were not probed.' `
            -Remediation 'Re-run discovery with a configuration containing subscription IDs.'
    }

    $probe = $Azure.Probes['Configured subscriptions']
    if ($probe.Status -ne 'Ok') {
        return New-LzReadinessCheck -Id 'R04' -Category 'Azure' -Name 'Subscription availability' -Status 'Warning' `
            -Detail "Subscription list could not be confirmed ($($probe.Status))."
    }

    $missing = @($probe.Items | Where-Object { -not $_.Accessible })
    if ($missing.Count -gt 0) {
        $ids = ($missing | ForEach-Object { $_.SubscriptionId }) -join ', '
        return New-LzReadinessCheck -Id 'R04' -Category 'Azure' -Name 'Subscription availability' -Status 'Fail' `
            -Detail "Not accessible to the signed-in account: $ids" `
            -Remediation 'Correct the subscription IDs in lz-config.json, or have an administrator grant the operator access. A subscription that is invisible now will fail at plan time.'
    }

    return New-LzReadinessCheck -Id 'R04' -Category 'Azure' -Name 'Subscription availability' -Status 'Pass' `
        -Detail "All $($probe.Count) configured subscriptions are accessible."
}

function Test-LzCanCreatePolicies {
    param([object]$Config)

    $scope = Get-LzManagementGroupScope $Config
    $defn = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Authorization/policyDefinitions/write'
    $asgn = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Authorization/policyAssignments/write'

    if ($defn.State -eq 'Pass' -and $asgn.State -eq 'Pass') {
        return New-LzReadinessCheck -Id 'R05' -Category 'Governance' -Name 'Create and assign policies' -Status 'Pass' `
            -Detail "Policy definition and assignment writes are permitted at $scope."
    }
    if ($defn.State -eq 'Warning' -or $asgn.State -eq 'Warning') {
        return New-LzReadinessCheck -Id 'R05' -Category 'Governance' -Name 'Create and assign policies' -Status 'Warning' `
            -Detail 'Policy permissions could not be read.' `
            -Remediation 'Grant Reader at the root management group so readiness can be assessed.'
    }
    return New-LzReadinessCheck -Id 'R05' -Category 'Governance' -Name 'Create and assign policies' -Status 'Fail' `
        -Detail "Policy writes are not permitted at $scope." `
        -Remediation 'Assign Resource Policy Contributor at the root management group. Without this the governance baseline cannot be deployed, which removes every guardrail the landing zone depends on.'
}

function Test-LzCanAssignRbac {
    param([object]$Config)

    $scope = Get-LzManagementGroupScope $Config
    $r = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Authorization/roleAssignments/write'

    switch ($r.State) {
        'Pass' {
            return New-LzReadinessCheck -Id 'R06' -Category 'Identity' -Name 'Assign RBAC roles' -Status 'Pass' `
                -Detail "Role assignment writes are permitted at $scope."
        }
        'Warning' {
            return New-LzReadinessCheck -Id 'R06' -Category 'Identity' -Name 'Assign RBAC roles' -Status 'Warning' `
                -Detail 'Role assignment permissions could not be read.'
        }
        default {
            return New-LzReadinessCheck -Id 'R06' -Category 'Identity' -Name 'Assign RBAC roles' -Status 'Fail' `
                -Detail "Microsoft.Authorization/roleAssignments/write is not permitted at $scope." `
                -Remediation 'Assign User Access Administrator or Owner at the root management group. The broker needs this to grant the per-environment plan and apply identities their roles.'
        }
    }
}

function Test-LzCanConfigureDiagnostics {
    param([object]$Config)

    $scope = Get-LzPrimarySubscriptionScope $Config
    $r = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Insights/diagnosticSettings/write'

    switch ($r.State) {
        'Pass' {
            return New-LzReadinessCheck -Id 'R07' -Category 'Observability' -Name 'Configure diagnostic settings' -Status 'Pass' `
                -Detail 'Diagnostic setting writes are permitted.'
        }
        'Warning' {
            return New-LzReadinessCheck -Id 'R07' -Category 'Observability' -Name 'Configure diagnostic settings' -Status 'Warning' `
                -Detail 'Diagnostic permissions could not be read.'
        }
        default {
            return New-LzReadinessCheck -Id 'R07' -Category 'Observability' -Name 'Configure diagnostic settings' -Status 'Fail' `
                -Detail "Microsoft.Insights/diagnosticSettings/write is not permitted at $scope." `
                -Remediation 'Assign Monitoring Contributor at the subscription or management group scope. Without diagnostics the landing zone deploys but emits no telemetry, and the compliance policy requiring diagnostics will report non-compliant.'
        }
    }
}

function Test-LzCanDeployNetworking {
    param([object]$Config, [object]$Azure)

    if ($Config.connectivity.model -eq 'none') {
        return New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Pass' `
            -Detail 'Connectivity model is "none"; no platform networking will be deployed.'
    }

    $scope = Get-LzPrimarySubscriptionScope $Config
    $r = Get-LzScopePermissionState -Scope $scope -Action 'Microsoft.Network/virtualNetworks/write'

    # An address-space collision is a hard blocker regardless of permissions.
    if ($Azure -and $Azure.AddressCollisions -and @($Azure.AddressCollisions).Count -gt 0) {
        $first = @($Azure.AddressCollisions)[0]
        return New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Fail' `
            -Detail ("Planned address space {0} overlaps existing VNet '{1}' ({2}). {3} collision(s) total." -f `
                     $first.PlannedCidr, $first.VNetName, $first.ExistingCidr, @($Azure.AddressCollisions).Count) `
            -Remediation 'Change the hub/spoke address spaces in the wizard so they do not overlap existing VNets. Peering will fail on overlapping ranges, and the failure surfaces only after the VNets are already created.'
    }

    switch ($r.State) {
        'Pass' {
            return New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Pass' `
                -Detail 'Virtual network writes are permitted and no address-space collisions were found.'
        }
        'Warning' {
            return New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Warning' `
                -Detail 'Network permissions could not be read.'
        }
        default {
            return New-LzReadinessCheck -Id 'R08' -Category 'Networking' -Name 'Deploy networking resources' -Status 'Fail' `
                -Detail "Microsoft.Network/virtualNetworks/write is not permitted at $scope." `
                -Remediation 'Assign Network Contributor (or Contributor) on the connectivity subscription.'
        }
    }
}

function Test-LzGitHubAccess {
    param([object]$Config, [object]$GitHub)

    if (-not $GitHub) {
        return New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Warning' `
            -Detail 'GitHub discovery did not run.' -Remediation 'Run: gh auth login, then re-run discovery.'
    }

    $auth = $GitHub.Probes['Authenticated identity']
    if ($auth.Status -ne 'Ok') {
        return New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Fail' `
            -Detail 'Not authenticated to GitHub.' -Remediation 'Run: gh auth login'
    }

    $cap = $GitHub.Capabilities
    $owner = $GitHub.Probes['Owner account']

    if ($owner.Status -eq 'Ok' -and -not $owner.Items[0].DeclarationMatches) {
        return New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Fail' `
            -Detail ("Configuration declares ownership model '{0}', but '{1}' is a {2} account." -f `
                     $cap.DeclaredModel, $GitHub.Owner, $cap.DetectedOwnerType) `
            -Remediation 'Correct github.ownershipModel in lz-config.json. The broker configures a different control set for each model, so a mismatch produces a repository missing the controls you expect.'
    }

    if ($cap.Limitations.Count -gt 0) {
        return New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Warning' `
            -Detail ($cap.Limitations -join ' ') `
            -Remediation 'Either accept the reduced control set explicitly, or move the repository to an organization on a paid plan. Every control that cannot be applied is listed by name in the bootstrap report.'
    }

    return New-LzReadinessCheck -Id 'R09' -Category 'GitHub' -Name 'GitHub access' -Status 'Pass' `
        -Detail ("Authenticated as '{0}'; {1} account supports environments and branch protection." -f `
                 $auth.Items[0].Login, $cap.DetectedOwnerType)
}

function Test-LzTerraformBackendAccess {
    param([object]$Config, [object]$Terraform)

    if (-not $Terraform) {
        return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Warning' `
            -Detail 'Terraform discovery did not run.'
    }

    $cap = $Terraform.Capabilities

    if ($Terraform.BackendType -eq 'hcp-terraform') {
        $credProbe = $Terraform.Probes['HCP Terraform credentials']
        if ($credProbe.Status -ne 'Ok') {
            return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Fail' `
                -Detail 'No HCP Terraform credentials found.' -Remediation 'Run: terraform login'
        }
        if (-not $cap.OrganizationReachable) {
            return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Fail' `
                -Detail "Organization '$($Config.backend.hcpTerraform.organization)' is not reachable with the current token." `
                -Remediation 'Check the organization name in lz-config.json, and confirm the token belongs to an account that is a member of it.'
        }
        if ($cap.Findings.Count -gt 0) {
            return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Warning' `
                -Detail ($cap.Findings -join ' ') `
                -Remediation 'Review the free-tier resource cap and any pre-existing workspaces before proceeding.'
        }
        return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Pass' `
            -Detail "Organization reachable; $($cap.CurrentManagedResources) of $($cap.FreeTierCap) free-tier resources currently managed."
    }

    # azurerm
    if ($cap.Findings.Count -gt 0) {
        $isSecurityFinding = @($cap.Findings | Where-Object { $_ -match 'public' }).Count -gt 0
        return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' `
            -Status $(if ($isSecurityFinding) { 'Fail' } else { 'Warning' }) `
            -Detail ($cap.Findings -join ' ') `
            -Remediation 'Terraform state must not be publicly reachable. Disable blob public access and restrict network access before storing state.'
    }
    return New-LzReadinessCheck -Id 'R10' -Category 'Terraform' -Name 'Terraform backend access' -Status 'Pass' `
        -Detail 'State storage account is present and not publicly exposed.'
}
