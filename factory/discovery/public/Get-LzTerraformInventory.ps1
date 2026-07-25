#Requires -Version 7.0
<#
    Terraform backend discovery — read-only.

    Covers both supported backends, because which one is in play changes what
    "backend is ready" even means:

      HCP Terraform  — organization reachable, workspace naming free or already
                       correct, variable sets visible, and (critically) the
                       managed-resource count against the 500 free-tier cap.
      azurerm        — state storage account exists or can be created, and is
                       not publicly reachable.

    The HCP token is read from the local Terraform credentials file that
    `terraform login` writes. It is never printed, never written to a report,
    and never passed on a command line.
#>

Set-StrictMode -Version Latest

# HCP Terraform free tier as of July 2026: 500 managed resources, unlimited
# users, one policy set of up to five policies. The legacy unlimited free plan
# ended 31 March 2026.
$script:LzHcpFreeRumCap = 500

function Get-LzTerraformInventory {
    <#
    .SYNOPSIS
        Inventory the configured Terraform state backend.
    .PARAMETER BackendType
        hcp-terraform | azurerm — from lz-config.json.
    .PARAMETER HcpOrganization
        HCP Terraform organization name.
    .PARAMETER WorkspacePrefix
        Workspaces are named {prefix}-{layer}; used to spot existing workspaces.
    .PARAMETER StorageAccountName
        azurerm backend state storage account.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('hcp-terraform', 'azurerm')][string]$BackendType = 'hcp-terraform',
        [string]$HcpOrganization = '',
        [string]$WorkspacePrefix = '',
        [string]$StorageAccountName = '',
        [string]$StateResourceGroupName = ''
    )

    Write-LzSection "Terraform backend discovery ($BackendType)"
    $probes = [ordered]@{}

    $probes['Terraform CLI'] = Invoke-LzProbe -Name 'Terraform CLI' -Probe {
        $v = & terraform version -json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'terraform CLI not found on PATH.' }
        $parsed = $v | ConvertFrom-Json -Depth 10
        @([pscustomobject]@{
            Version  = $parsed.terraform_version
            Platform = $parsed.platform
            Outdated = if ($parsed.PSObject.Properties.Name -contains 'terraform_outdated') { $parsed.terraform_outdated } else { $false }
        })
    }

    if ($BackendType -eq 'hcp-terraform') {
        $token = Get-LzHcpToken

        $probes['HCP Terraform credentials'] = Invoke-LzProbe -Name 'HCP Terraform credentials' -Probe {
            if (-not $token) { throw 'Not logged in. Run: terraform login' }
            @([pscustomobject]@{ Source = '~/.terraform.d/credentials.tfrc.json'; TokenPresent = $true })
        }

        if ($token) {
            $probes['HCP organizations'] = Invoke-LzProbe -Name 'HCP organizations' -ForbiddenRemediation `
                'The HCP Terraform token is not authorized to list organizations. Re-run: terraform login' -Probe {
                $r = Invoke-LzHcpApi -Token $token -Path 'organizations'
                if (-not $r -or -not $r.data) { return @() }
                @($r.data | ForEach-Object {
                    [pscustomobject]@{ Name = $_.attributes.name; Email = $_.attributes.email }
                })
            }

            if ($HcpOrganization) {
                $probes['HCP workspaces'] = Invoke-LzProbe -Name 'HCP workspaces' -ForbiddenRemediation `
                    "Cannot list workspaces in organization '$HcpOrganization'. Confirm the organization name and that the token has access." -Probe {
                    $r = Invoke-LzHcpApi -Token $token -Path "organizations/$HcpOrganization/workspaces?page%5Bsize%5D=100"
                    if (-not $r -or -not $r.data) { return @() }
                    @($r.data | ForEach-Object {
                        [pscustomobject]@{
                            Name          = $_.attributes.name
                            ExecutionMode = $_.attributes.'execution-mode'
                            ResourceCount = $_.attributes.'resource-count'
                            TerraformVersion = $_.attributes.'terraform-version'
                            MatchesPrefix = ($WorkspacePrefix -and $_.attributes.name -like "$WorkspacePrefix-*")
                        }
                    })
                }

                $probes['HCP variable sets'] = Invoke-LzProbe -Name 'HCP variable sets' -Probe {
                    $r = Invoke-LzHcpApi -Token $token -Path "organizations/$HcpOrganization/varsets"
                    if (-not $r -or -not $r.data) { return @() }
                    @($r.data | ForEach-Object {
                        [pscustomobject]@{
                            Name        = $_.attributes.name
                            Global      = $_.attributes.global
                            Description = $_.attributes.description
                        }
                    })
                }

                $probes['HCP policy sets'] = Invoke-LzProbe -Name 'HCP policy sets' -Probe {
                    $r = Invoke-LzHcpApi -Token $token -Path "organizations/$HcpOrganization/policy-sets"
                    if (-not $r -or -not $r.data) { return @() }
                    @($r.data | ForEach-Object {
                        [pscustomobject]@{
                            Name       = $_.attributes.name
                            Kind       = if ($_.attributes.PSObject.Properties.Name -contains 'kind') { $_.attributes.kind } else { 'sentinel' }
                            PolicyCount = $_.attributes.'policy-count'
                            Global     = $_.attributes.global
                        }
                    })
                }
            }
        }
    }
    else {
        # ── azurerm backend ──────────────────────────────────────────────────
        if ($StorageAccountName) {
            $probes['State storage account'] = Invoke-LzProbe -Name 'State storage account' -Probe {
                $q = "Resources | where type =~ 'microsoft.storage/storageaccounts' and name =~ '$StorageAccountName' | project name, resourceGroup, subscriptionId, location, publicNetworkAccess = properties.publicNetworkAccess, allowBlobPublicAccess = properties.allowBlobPublicAccess, minimumTlsVersion = properties.minimumTlsVersion"
                $r = Invoke-LzAz graph query -q $q --first 10
                if (-not $r -or -not $r.data) { return @() }
                @($r.data | ForEach-Object {
                    [pscustomobject]@{
                        Name                  = $_.name
                        ResourceGroup         = $_.resourceGroup
                        SubscriptionId        = $_.subscriptionId
                        Location              = $_.location
                        PublicNetworkAccess   = $_.publicNetworkAccess
                        AllowBlobPublicAccess = $_.allowBlobPublicAccess
                        MinimumTlsVersion     = $_.minimumTlsVersion
                    }
                })
            }
        }
    }

    foreach ($p in $probes.Values) { Write-LzProbeResult $p }

    [pscustomobject]@{
        Domain       = 'Terraform'
        BackendType  = $BackendType
        Probes       = $probes
        Capabilities = Get-LzTerraformCapabilities -Probes $probes -BackendType $BackendType `
                          -HcpOrganization $HcpOrganization -WorkspacePrefix $WorkspacePrefix
    }
}

function Get-LzHcpToken {
    <#
    .SYNOPSIS
        Read the HCP Terraform token written by `terraform login`.
    .DESCRIPTION
        Returned in memory only. Callers must never write it to a report; the
        report generator additionally redacts anything token-shaped on the way
        out as a second line of defence.
    #>
    [CmdletBinding()]
    param([string]$Hostname = 'app.terraform.io')

    $paths = @(
        (Join-Path $HOME '.terraform.d/credentials.tfrc.json'),
        (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'terraform.d/credentials.tfrc.json')
    )

    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        try {
            $creds = Get-Content $p -Raw | ConvertFrom-Json -Depth 10
            if ($creds.credentials -and $creds.credentials.PSObject.Properties.Name -contains $Hostname) {
                return $creds.credentials.$Hostname.token
            }
        }
        catch { continue }
    }

    # Environment fallback, used by CI.
    if ($env:TF_TOKEN_app_terraform_io) { return $env:TF_TOKEN_app_terraform_io }
    return $null
}

function Invoke-LzHcpApi {
    <#
    .SYNOPSIS
        Read-only GET against the HCP Terraform API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Path,
        [string]$Hostname = 'app.terraform.io'
    )

    $uri = "https://$Hostname/api/v2/$Path"
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type'  = 'application/vnd.api+json'
    }

    try {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($status -eq 401 -or $status -eq 403) { throw "Forbidden (HTTP $status) calling $Path" }
        if ($status -eq 404) { return $null }
        throw $_.Exception.Message
    }
}

function Get-LzTerraformCapabilities {
    <#
    .SYNOPSIS
        Assess backend readiness, including the HCP free-tier resource cap.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Probes,
        [Parameter(Mandatory)][string]$BackendType,
        [string]$HcpOrganization = '',
        [string]$WorkspacePrefix = ''
    )

    $findings = @()
    $orgReachable = $false
    $existingWorkspaces = @()
    $currentRum = 0

    if ($BackendType -eq 'hcp-terraform') {
        $orgProbe = if ($Probes.Contains('HCP organizations')) { $Probes['HCP organizations'] } else { $null }
        if ($orgProbe -and $orgProbe.Status -eq 'Ok' -and $HcpOrganization) {
            $orgReachable = @($orgProbe.Items | Where-Object { $_.Name -eq $HcpOrganization }).Count -gt 0
            if (-not $orgReachable) {
                $findings += "Organization '$HcpOrganization' was not found among the organizations this token can see. Check the name for typos."
            }
        }

        $wsProbe = if ($Probes.Contains('HCP workspaces')) { $Probes['HCP workspaces'] } else { $null }
        if ($wsProbe -and $wsProbe.Status -eq 'Ok') {
            $existingWorkspaces = @($wsProbe.Items | Where-Object { $_.MatchesPrefix })
            if ($existingWorkspaces.Count -gt 0) {
                $findings += "$($existingWorkspaces.Count) workspace(s) already use the prefix '$WorkspacePrefix'. The broker reconciles rather than recreating, but confirm these belong to this landing zone."
            }

            # Total managed resources already in the organization. This is what
            # counts against the free-tier cap, not just this landing zone.
            $currentRum = (@($wsProbe.Items | ForEach-Object { [int]($_.ResourceCount ?? 0) }) | Measure-Object -Sum).Sum
            if ($currentRum -ge $script:LzHcpFreeRumCap) {
                $findings += "The organization already manages $currentRum resources, at or above the $($script:LzHcpFreeRumCap)-resource free-tier cap. Deploying this landing zone will incur charges on a paid tier."
            }
            elseif ($currentRum -gt ($script:LzHcpFreeRumCap * 0.6)) {
                $findings += "The organization already manages $currentRum of the $($script:LzHcpFreeRumCap) free-tier resources. Adding a landing zone will likely exceed the cap."
            }
        }

        $psProbe = if ($Probes.Contains('HCP policy sets')) { $Probes['HCP policy sets'] } else { $null }
        if ($psProbe -and $psProbe.Status -eq 'Ok' -and $psProbe.Count -ge 1) {
            $findings += "$($psProbe.Count) policy set(s) already exist. The free tier permits one policy set of up to five policies."
        }
    }
    else {
        $saProbe = if ($Probes.Contains('State storage account')) { $Probes['State storage account'] } else { $null }
        if ($saProbe -and $saProbe.Status -eq 'Ok') {
            $sa = $saProbe.Items[0]
            if ($sa.AllowBlobPublicAccess -eq $true) {
                $findings += "State storage account '$($sa.Name)' allows blob public access. Terraform state routinely contains resource IDs and occasionally secrets; this must be disabled."
            }
            if ($sa.PublicNetworkAccess -eq 'Enabled') {
                $findings += "State storage account '$($sa.Name)' is reachable from the public internet. Restrict to a private endpoint or a network rule set."
            }
        }
        elseif ($saProbe -and $saProbe.Status -eq 'Empty') {
            $findings += 'The state storage account does not exist yet. terraform/backend-bootstrap/ creates it with local state, after which state is migrated — that ordering is inherent to this backend.'
        }
    }

    [pscustomobject]@{
        BackendType            = $BackendType
        OrganizationReachable  = $orgReachable
        ExistingWorkspaces     = $existingWorkspaces
        CurrentManagedResources = $currentRum
        FreeTierCap            = $script:LzHcpFreeRumCap
        Findings               = $findings
    }
}
