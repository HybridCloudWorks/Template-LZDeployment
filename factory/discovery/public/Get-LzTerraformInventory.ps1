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
        azurerm — the only supported value (ADR 0015). The parameter survives
        so older callers fail with a clear message rather than a binding error.
    .PARAMETER StorageAccountName
        Declared state storage account name from backend.azurerm.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('azurerm')][string]$BackendType = 'azurerm',
        [string]$StorageAccountName = '',
        [string]$StateResourceGroupName = ''
    )

    $probes = [ordered]@{}

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
        BackendType  = 'azurerm'
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
