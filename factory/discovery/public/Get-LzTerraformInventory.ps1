#Requires -Version 7.0
<#
    Discovery — Terraform backend inventory.

    Read-only probes of the azurerm state backend (ADR 0015: azurerm is the
    only backend the generator emits). Confirms the declared state storage
    account exists (or that the name is free to create) and reports its
    security posture. Never mutates anything.
#>

Set-StrictMode -Version Latest

function Get-LzTerraformInventory {
    <#
    .SYNOPSIS
        Probe the Terraform state backend declared in lz-config.json.
    .PARAMETER BackendType
        azurerm or hcp-terraform. Decision 0023 added the second backend for
        STATE ONLY; this parameter was still ValidateSet('azurerm') afterwards,
        so the two shipped out of step and every HCP client was inventoried as
        though their state lived in Azure.
    .PARAMETER StorageAccountName
        Declared state storage account name from backend.azurerm. Not supplied,
        and not meaningful, under hcp-terraform.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('azurerm', 'hcp-terraform')][string]$BackendType = 'azurerm',
        [string]$StorageAccountName = '',
        [string]$StateResourceGroupName = ''
    )

    $probes = [ordered]@{}

    # There is nothing in THIS tenant to probe for an HCP Terraform backend:
    # the state lives in HCP, reachable with TF_TOKEN rather than with the az
    # session discovery is running under. Probing anyway would report an
    # Azure storage account that is not the state store, which is worse than
    # reporting nothing — R10 would then pass or fail on the wrong object.
    if ($BackendType -eq 'hcp-terraform') { $StorageAccountName = '' }

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

    foreach ($p in $probes.Values) { Write-LzProbeResult $p }

    [pscustomobject]@{
        Domain       = 'Terraform'
        BackendType  = $BackendType
        Probes       = $probes
        Capabilities = Get-LzTerraformCapabilities -Probes $probes
    }
}

function Get-LzTerraformCapabilities {
    <#
    .SYNOPSIS
        Assess azurerm state-backend readiness from the probe results.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Probes
    )

    $findings = @()
    $accountExists = $false

    $saProbe = if ($Probes.Contains('State storage account')) { $Probes['State storage account'] } else { $null }
    if ($saProbe -and $saProbe.Status -eq 'Ok') {
        $accountExists = @($saProbe.Items).Count -gt 0
        if ($accountExists) {
            $account = @($saProbe.Items)[0]
            $findings += "State storage account '$($account.Name)' already exists in resource group '$($account.ResourceGroup)'. The broker reconciles rather than recreating, but confirm it belongs to this landing zone."
            if ("$($account.AllowBlobPublicAccess)" -eq 'True') {
                $findings += 'The existing state storage account allows public blob access. The broker will disable it.'
            }
        }
        else {
            $findings += 'The declared state storage account does not exist yet; the broker will create it with AAD-only auth, TLS 1.2 minimum, and public access disabled.'
        }
    }

    [pscustomobject]@{
        BackendReady        = $true
        StateAccountExists  = $accountExists
        Findings            = $findings
    }
}
