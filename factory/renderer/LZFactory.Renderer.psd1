@{
    RootModule        = 'LZFactory.Renderer.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c9f5d3b2-8e4a-4a7c-bd16-2f3b4c5d6e7f'
    Author            = 'Landing Zone Factory'
    Description       = 'Template rendering engine for the Azure Landing Zone Factory. Resolves {{FACTORY:...}} tokens and conditional directives against a validated configuration, enforces fail-closed render guards, and detects drift between the configuration schema and the Terraform variables the corpus declares.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Invoke-LzRender'
        'Resolve-LzTemplate'
        'Test-LzRenderGuards'
        'Test-LzSchemaDrift'
        'New-LzRenderContext'
        'New-LzScopedContext'
        'Get-LzActiveLayers'
        'Get-LzTokenValue'
        'Test-LzExpression'
        'Test-LzTruthy'
        'Test-LzPathDefined'
        'Expand-LzTokens'
        'Expand-LzDirectives'
        'Assert-LzNoResidualTokens'
        'ConvertTo-LzHclString'
        'ConvertTo-LzHclList'
        'ConvertTo-LzHclMap'
        'ConvertTo-LzBoolLiteral'
        'Get-LzTerraformVariables'
        'Get-LzSchemaPaths'
        'Get-LzSchemaPattern'
        'Get-LzConstraintCounterexample'
        'Test-LzRendererCidrOverlap'
        'New-LzGuardViolation'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Azure', 'LandingZone', 'CAF', 'Terraform', 'Renderer', 'Templating')
            ProjectUri   = 'https://github.com/saulpatinojr/HCW-Plan_LZDeployment'
            ReleaseNotes = 'Initial release. Factory stage 5.'
        }
    }
}
