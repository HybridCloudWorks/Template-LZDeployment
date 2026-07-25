@{
    RootModule        = 'LZFactory.Discovery.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b8e4c2a1-7d39-4f6b-9c05-1e2a3b4c5d6e'
    Author            = 'Landing Zone Factory'
    Description       = 'Phase 0 discovery engine for the Azure Landing Zone Factory. Read-only inventory of GitHub, Microsoft Entra ID, Azure, and the Terraform state backend, plus tenant readiness validation. Creates, modifies, and deletes nothing.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Invoke-LzDiscovery'
        'Get-LzGitHubInventory'
        'Get-LzEntraInventory'
        'Get-LzAzureInventory'
        'Get-LzTerraformInventory'
        'Test-LzTenantReadiness'
        'New-LzReadinessReport'
        'Export-LzDiscoveryInventory'
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'LandingZone', 'CAF', 'Terraform', 'Discovery', 'ReadOnly')
            ProjectUri   = 'https://github.com/saulpatinojr/HCW-Plan_LZDeployment'
            ReleaseNotes = 'Initial release. Factory stage 4.'
        }
    }
}
