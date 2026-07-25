#Requires -Version 7.0
<#
    Microsoft Entra ID discovery — read-only.

    Two findings here disproportionately affect the deployment:

      1. Federated credential count. An application is limited to 20 federated
         identity credentials. The factory's per-environment identity model keeps
         each app well under that, but a brownfield tenant reusing one app for
         everything can already be at the ceiling (risk OI3).

      2. Conditional Access. A policy that requires a compliant device or blocks
         non-interactive sign-in can break workload identity federation in ways
         that only appear at the first CI run, long after bootstrap "succeeded".
         We surface CA policies here so that failure mode is anticipated rather
         than debugged.
#>

Set-StrictMode -Version Latest

function Get-LzEntraInventory {
    <#
    .SYNOPSIS
        Inventory Entra ID objects relevant to landing zone identity.
    .PARAMETER TenantId
        Expected tenant. Compared against the signed-in context to catch the
        common error of running discovery against the wrong tenant.
    .PARAMETER NamePrefix
        Optional filter (typically the company short name) so app registration
        listing stays useful in a tenant with thousands of apps.
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId = '',
        [string]$NamePrefix = ''
    )

    Write-LzSection 'Microsoft Entra ID discovery'
    $probes = [ordered]@{}

    # ── Signed-in context ────────────────────────────────────────────────────
    $probes['Signed-in context'] = Invoke-LzProbe -Name 'Signed-in context' -ForbiddenRemediation `
        'Run: az login --tenant <tenantId>' -Probe {
        $acct = Invoke-LzAz account show
        if (-not $acct) { return @() }
        @([pscustomobject]@{
            TenantId        = $acct.tenantId
            SubscriptionId  = $acct.id
            User            = $acct.user.name
            UserType        = $acct.user.type
            TenantMatches   = ([string]::IsNullOrEmpty($TenantId) -or $acct.tenantId -eq $TenantId)
            ExpectedTenant  = $TenantId
        })
    }

    # ── Directory roles held by the operator ─────────────────────────────────
    # This determines whether app registration and federated credential creation
    # will succeed. Checked by reading role membership, never by attempting a
    # create-and-delete.
    $probes['Directory roles'] = Invoke-LzProbe -Name 'Directory roles' -ForbiddenRemediation `
        'The signed-in account cannot read its own directory role memberships. Grant at least Directory Readers, or have an administrator confirm the roles listed in docs/identity-trust-matrix.md.' -Probe {
        $resp = Invoke-LzGraphApi -Url 'https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=displayName,roleTemplateId'
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | ForEach-Object {
            [pscustomobject]@{ DisplayName = $_.displayName; RoleTemplateId = $_.roleTemplateId }
        })
    }

    # ── App registrations ────────────────────────────────────────────────────
    # NOTE ON WINDOWS ARGUMENT PASSING
    # --------------------------------
    # An OData filter such as startswith(displayName,'x') cannot be passed as an
    # `az` argument on Windows: PowerShell does not quote arguments containing
    # parentheses, and the az.cmd shim then hands unbalanced parens to cmd, which
    # fails with "--query was unexpected at this time". Calling Graph directly
    # with the filter percent-encoded in the URL keeps every parenthesis out of
    # the command line, and behaves identically on Linux and macOS.
    $probes['App registrations'] = Invoke-LzProbe -Name 'App registrations' -ForbiddenRemediation `
        'Cannot list application registrations. Application Administrator (or Cloud Application Administrator) is required to create the OIDC apps this deployment needs.' -Probe {
        $url = 'https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName,signInAudience&$top=200'
        if ($NamePrefix) { $url += '&$filter=' + (ConvertTo-LzODataStartsWith -Property 'displayName' -Value $NamePrefix) }

        $resp = Invoke-LzGraphApi -Url $url
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | ForEach-Object {
            [pscustomobject]@{
                DisplayName    = $_.displayName
                AppId          = $_.appId
                Id             = $_.id
                SignInAudience = $_.signInAudience
            }
        })
    }

    # ── Federated credentials on discovered apps ─────────────────────────────
    # The 20-credential-per-app ceiling only matters for apps we might reuse, so
    # this walks the apps found above rather than the whole directory.
    $probes['Federated credentials'] = Invoke-LzProbe -Name 'Federated credentials' -Probe {
        $appProbe = $probes['App registrations']
        if ($appProbe.Status -ne 'Ok') { return @() }

        $results = @()
        # Cap the walk: a tenant with thousands of apps would otherwise turn
        # discovery into a rate-limit incident.
        foreach ($app in @($appProbe.Items | Select-Object -First 40)) {
            try {
                $creds = Invoke-LzAz ad app federated-credential list --id $app.AppId
                foreach ($c in @($creds)) {
                    $results += [pscustomobject]@{
                        AppDisplayName = $app.DisplayName
                        AppId          = $app.AppId
                        CredentialName = $c.name
                        Issuer         = $c.issuer
                        Subject        = $c.subject
                        Audiences      = ($c.audiences -join ', ')
                    }
                }
            }
            catch {
                # A single unreadable app must not void the whole probe, but it
                # also must not look like "this app has no credentials".
                $results += [pscustomobject]@{
                    AppDisplayName = $app.DisplayName
                    AppId          = $app.AppId
                    CredentialName = '<unreadable>'
                    Issuer         = ''
                    Subject        = ''
                    Audiences      = ''
                }
            }
        }
        @($results)
    }

    # ── Service principals ───────────────────────────────────────────────────
    $probes['Service principals'] = Invoke-LzProbe -Name 'Service principals' -Probe {
        $url = 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName&$top=200'
        if ($NamePrefix) { $url += '&$filter=' + (ConvertTo-LzODataStartsWith -Property 'displayName' -Value $NamePrefix) }

        $resp = Invoke-LzGraphApi -Url $url
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | ForEach-Object {
            [pscustomobject]@{ DisplayName = $_.displayName; AppId = $_.appId; Id = $_.id }
        })
    }

    # ── User-assigned managed identities ─────────────────────────────────────
    $probes['Managed identities'] = Invoke-LzProbe -Name 'Managed identities' -Probe {
        $mis = Invoke-LzAz identity list --query '[].{Name:name,ResourceGroup:resourceGroup,ClientId:clientId,Location:location}'
        if (-not $mis) { return @() }
        @($mis)
    }

    # ── Administrative units ─────────────────────────────────────────────────
    $probes['Administrative units'] = Invoke-LzProbe -Name 'Administrative units' -Probe {
        $resp = Invoke-LzGraphApi -Url 'https://graph.microsoft.com/v1.0/directory/administrativeUnits?$select=id,displayName'
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | ForEach-Object { [pscustomobject]@{ Id = $_.id; DisplayName = $_.displayName } })
    }

    # ── Conditional Access ───────────────────────────────────────────────────
    $probes['Conditional Access policies'] = Invoke-LzProbe -Name 'Conditional Access policies' -ForbiddenRemediation `
        'Conditional Access policies could not be read (requires Policy.Read.All or a directory role such as Security Reader). CA policies can block workload identity federation at the first CI run even though bootstrap succeeded — treat this as an unknown, not a pass.' -Probe {
        $resp = Invoke-LzGraphApi -Url 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | ForEach-Object {
            [pscustomobject]@{
                DisplayName    = $_.displayName
                State          = $_.state
                # Surfaced because these three conditions are the ones that
                # most commonly break service-principal and federated sign-in.
                TargetsAllApps = ($_.conditions.applications.includeApplications -contains 'All')
                GrantControls  = if ($_.grantControls) { ($_.grantControls.builtInControls -join ', ') } else { '' }
            }
        })
    }

    foreach ($p in $probes.Values) { Write-LzProbeResult $p }

    [pscustomobject]@{
        Domain       = 'Entra'
        TenantId     = $TenantId
        Probes       = $probes
        Capabilities = Get-LzEntraCapabilities -Probes $probes
    }
}

function Get-LzEntraCapabilities {
    <#
    .SYNOPSIS
        Derive whether the operator can create the identity objects the factory needs.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Probes)

    # Roles that permit application registration + federated credential management.
    $appAdminRoles = @(
        'Global Administrator', 'Application Administrator', 'Cloud Application Administrator'
    )

    $roleProbe = $Probes['Directory roles']
    $heldRoles = @()
    if ($roleProbe.Status -eq 'Ok') { $heldRoles = @($roleProbe.Items | ForEach-Object { $_.DisplayName }) }

    $canManageApps = @($heldRoles | Where-Object { $_ -in $appAdminRoles }).Count -gt 0
    $rolesReadable = ($roleProbe.Status -eq 'Ok' -or $roleProbe.Status -eq 'Empty')

    # Any app already at or near the federated-credential ceiling.
    $fedProbe = $Probes['Federated credentials']
    $nearLimit = @()
    if ($fedProbe.Status -eq 'Ok') {
        $nearLimit = @(
            $fedProbe.Items | Group-Object AppId | Where-Object { $_.Count -ge 18 } | ForEach-Object {
                [pscustomobject]@{ AppId = $_.Name; CredentialCount = $_.Count }
            }
        )
    }

    $caProbe = $Probes['Conditional Access policies']
    $caEnabledTargetingAllApps = @()
    if ($caProbe.Status -eq 'Ok') {
        $caEnabledTargetingAllApps = @(
            $caProbe.Items | Where-Object { $_.State -eq 'enabled' -and $_.TargetsAllApps }
        )
    }

    [pscustomobject]@{
        HeldDirectoryRoles          = $heldRoles
        RolesReadable               = $rolesReadable
        CanManageApplications       = $canManageApps
        AppsNearFederatedCredLimit  = $nearLimit
        CaPoliciesTargetingAllApps  = $caEnabledTargetingAllApps
        CaPoliciesReadable          = ($caProbe.Status -in @('Ok', 'Empty'))
    }
}
