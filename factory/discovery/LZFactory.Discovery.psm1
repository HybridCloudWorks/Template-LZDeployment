#Requires -Version 7.0
<#
    LZFactory.Discovery — Phase 0 discovery engine for the Azure Landing Zone
    Factory.

    Read-only by contract. Every command it issues is a list/get; Assert-LzReadOnly
    structurally rejects mutating verbs so a future edit cannot quietly introduce
    a write into what operators are told is a safe-to-run assessment.

    Import:
        Import-Module ./factory/discovery/LZFactory.Discovery.psd1

    Run:
        Invoke-LzDiscovery -ConfigPath ./generated-output/contoso/lz-config.json
#>

Set-StrictMode -Version Latest

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

# Private first: public probes depend on the shared helpers.
foreach ($file in @($private) + @($public)) {
    try { . $file.FullName }
    catch { throw "Failed to load $($file.Name): $($_.Exception.Message)" }
}

Export-ModuleMember -Function @(
    'Invoke-LzDiscovery'
    'Get-LzGitHubInventory'
    'Get-LzEntraInventory'
    'Get-LzAzureInventory'
    'Get-LzTerraformInventory'
    'Test-LzTenantReadiness'
    'New-LzReadinessReport'
    'Export-LzDiscoveryInventory'
    # Exported for unit testing and reuse by later factory stages.
    'Test-LzCidrOverlap'
    'Get-LzAddressSpaceCollision'
    'Test-LzWildcardMatch'
    'Test-LzActionPermitted'
    'New-LzReadinessCheck'
    'New-LzProbeResult'
    'Invoke-LzProbe'
    'Assert-LzReadOnly'
    'Protect-LzSecretText'
    'ConvertTo-LzSafeString'
    'Get-LzTerseMessage'
    'Test-LzForbiddenError'
    'Test-LzUnavailableError'
)
