#Requires -Version 7.0
<#
    Discovery orchestrator — Phase 0.

    Reads lz-config.json, runs every probe domain, validates readiness, and
    writes both report artifacts. Read-only throughout.

    A failure in one domain does not abort the others: an operator who is signed
    in to Azure but not GitHub should still get their Azure inventory, with the
    GitHub gap reported honestly rather than the whole run collapsing.
#>

Set-StrictMode -Version Latest

function Invoke-LzDiscovery {
    <#
    .SYNOPSIS
        Run the full Phase 0 discovery and readiness assessment.
    .PARAMETER ConfigPath
        Path to lz-config.json exported from the wizard. Optional: without it,
        discovery still inventories what it can, but readiness checks that depend
        on configured scopes are reported as unconfirmed.
    .PARAMETER OutputDirectory
        Where the report and inventory are written. Defaults to the config's
        directory, so artifacts land beside the configuration they describe.
    .PARAMETER SkipDomain
        One or more of GitHub, Entra, Azure, Terraform to skip.
    .EXAMPLE
        Invoke-LzDiscovery -ConfigPath ./generated-output/contoso/lz-config.json
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = '',
        [string]$OutputDirectory = '',
        [ValidateSet('GitHub', 'Entra', 'Azure', 'Terraform')][string[]]$SkipDomain = @(),
        [switch]$Quiet
    )

    $script:LzQuiet = [bool]$Quiet
    $started = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-LzHeader 'Landing Zone Factory — Discovery Engine (Phase 0)' 'Read-only. Nothing is created, modified, or deleted.'

    # ── Configuration ────────────────────────────────────────────────────────
    $config = $null
    if ($ConfigPath) {
        if (-not (Test-Path $ConfigPath)) { throw "Configuration not found: $ConfigPath" }
        try { $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 25 }
        catch { throw "Configuration is not valid JSON: $($_.Exception.Message)" }

        Write-LzOK "Loaded configuration for '$($config.organization.companyName)'"
        Write-LzInfo "Schema $($config.schemaVersion), factory v$($config.factoryVersion), mode: $($config.deploymentStrategy.mode)"

        if (-not $OutputDirectory) { $OutputDirectory = Split-Path -Parent (Resolve-Path $ConfigPath) }
    }
    else {
        Write-LzWarn 'No configuration supplied. Running an unscoped inventory; readiness checks that need configured scopes will report as unconfirmed.'
        if (-not $OutputDirectory) { $OutputDirectory = '.' }
    }

    $factoryVersion = Get-LzFactoryVersion

    # ── Domain probes ────────────────────────────────────────────────────────
    $github = $null; $entra = $null; $azure = $null; $terraform = $null

    if ('GitHub' -notin $SkipDomain -and $config) {
        $github = Invoke-LzDomainSafely -Name 'GitHub' -Action {
            Get-LzGitHubInventory `
                -OwnerName $config.github.ownerName `
                -RepositoryName $config.github.repositoryName `
                -OwnershipModel $config.github.ownershipModel `
                -EnterpriseSlug $(if ($config.github.PSObject.Properties.Name -contains 'enterpriseSlug') { $config.github.enterpriseSlug } else { '' })
        }
    }

    if ('Entra' -notin $SkipDomain) {
        $entra = Invoke-LzDomainSafely -Name 'Entra' -Action {
            Get-LzEntraInventory `
                -TenantId $(if ($config) { $config.azure.tenantId } else { '' }) `
                -NamePrefix $(if ($config) { "sp-$($config.organization.companyShortName)" } else { '' })
        }
    }

    if ('Azure' -notin $SkipDomain) {
        $azure = Invoke-LzDomainSafely -Name 'Azure' -Action {
            $subs = @()
            $root = ''
            $cidrs = @()
            if ($config) {
                $subs = @($config.azure.subscriptions.PSObject.Properties |
                          ForEach-Object { $_.Value } | Where-Object { $_ })
                $root = $config.azure.managementGroups.rootId
                $cidrs = Get-LzPlannedCidrs -Config $config
            }
            Get-LzAzureInventory -SubscriptionIds $subs -ManagementGroupRootId $root -PlannedAddressSpaces $cidrs
        }
    }

    if ('Terraform' -notin $SkipDomain -and $config) {
        $terraform = Invoke-LzDomainSafely -Name 'Terraform' -Action {
            $p = @{ BackendType = $config.backend.type }
            if ($config.backend.type -eq 'hcp-terraform') {
                $p['HcpOrganization'] = $config.backend.hcpTerraform.organization
                $p['WorkspacePrefix'] = $config.backend.hcpTerraform.workspacePrefix
            }
            else {
                $p['StorageAccountName']     = $config.backend.azurerm.storageAccountName
                $p['StateResourceGroupName'] = $config.backend.azurerm.resourceGroupName
            }
            Get-LzTerraformInventory @p
        }
    }

    # ── Readiness ────────────────────────────────────────────────────────────
    $readiness = $null
    if ($config) {
        $readiness = Test-LzTenantReadiness -Config $config `
            -GitHubInventory $github -EntraInventory $entra `
            -AzureInventory $azure -TerraformInventory $terraform
    }

    $sw.Stop()

    $discovery = [pscustomobject]@{
        GeneratedAt     = $started.ToUniversalTime().ToString('o')
        FactoryVersion  = $factoryVersion
        DurationSeconds = $sw.Elapsed.TotalSeconds
        ConfigPath      = $ConfigPath
        Config          = $config
        GitHub          = $github
        Entra           = $entra
        Azure           = $azure
        Terraform       = $terraform
        Readiness       = $readiness
    }

    # ── Artifacts ────────────────────────────────────────────────────────────
    $reportPath = Join-Path $OutputDirectory 'tenant-readiness-report.md'
    $inventoryPath = Join-Path $OutputDirectory 'discovery-inventory.json'

    New-LzReadinessReport -Discovery $discovery -Path $reportPath | Out-Null
    Export-LzDiscoveryInventory -Discovery $discovery -Path $inventoryPath | Out-Null

    Write-LzSection 'Discovery complete'
    Write-LzOK "Report:    $reportPath"
    Write-LzOK "Inventory: $inventoryPath"

    if ($readiness) {
        if ($readiness.FailCount -gt 0) {
            Write-LzFail "NOT READY — $($readiness.FailCount) blocking issue(s). See the report."
        }
        elseif ($readiness.WarningCount -gt 0) {
            Write-LzWarn "READY WITH CAVEATS — $($readiness.WarningCount) item(s) need your decision."
        }
        else {
            Write-LzOK 'READY — all checks passed.'
        }
    }

    return $discovery
}

function Invoke-LzDomainSafely {
    <#
    .SYNOPSIS
        Run one domain's probes; convert an unexpected failure into a reported
        result rather than aborting the whole discovery run.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try { return & $Action }
    catch {
        Write-LzFail "$Name discovery failed: $(Protect-LzSecretText $_.Exception.Message)"
        return [pscustomobject]@{
            Domain = $Name
            Probes = [ordered]@{
                "$Name discovery" = New-LzProbeResult -Name "$Name discovery" -Status Error `
                    -Message (Protect-LzSecretText $_.Exception.Message)
            }
            Capabilities = [pscustomobject]@{ Limitations = @("$Name discovery could not run.") }
        }
    }
}

function Get-LzPlannedCidrs {
    <#
    .SYNOPSIS
        Extract the planned hub/spoke address spaces from the configuration.
    #>
    param([Parameter(Mandatory)][object]$Config)

    if ($Config.connectivity.model -ne 'hub-spoke') { return @() }
    if (-not ($Config.connectivity.PSObject.Properties.Name -contains 'hubSpoke')) { return @() }

    $hs = $Config.connectivity.hubSpoke
    return @(
        $hs.primaryHubAddressSpace
        $hs.drHubAddressSpace
        $hs.primarySpokeAddressSpace
        $hs.drSpokeAddressSpace
    ) | Where-Object { $_ }
}

function Get-LzFactoryVersion {
    <#
    .SYNOPSIS
        Read factoryVersion from factory-version.json at the repository root.
    #>
    $candidates = @(
        (Join-Path $PSScriptRoot '../../../factory-version.json'),
        (Join-Path (Get-Location) 'factory-version.json')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            try { return (Get-Content $c -Raw | ConvertFrom-Json -Depth 10).factoryVersion }
            catch { continue }
        }
    }
    return 'unknown'
}
