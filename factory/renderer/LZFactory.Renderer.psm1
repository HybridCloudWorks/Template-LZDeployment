#Requires -Version 7.0
<#
    LZFactory.Renderer — template rendering engine for the Azure Landing Zone
    Factory.

    Turns a validated lz-config.json plus the template corpus into a rendered
    customer repository. Fails closed on unknown tokens, unbalanced directives,
    unresolved placeholders, and any configuration the module corpus cannot
    actually deliver.

    Import:
        Import-Module ./factory/renderer/LZFactory.Renderer.psd1

    Run:
        Invoke-LzRender -ConfigPath ./generated-output/contoso/lz-config.json `
                        -OutputDirectory ./generated-output/contoso/repo
#>

Set-StrictMode -Version Latest

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private) + @($public)) {
    try { . $file.FullName }
    catch { throw "Failed to load $($file.Name): $($_.Exception.Message)" }
}

Export-ModuleMember -Function @(
    'Invoke-LzRender'
    'Resolve-LzTemplate'
    # Exported so factory/ci/Test-SchemaCoverage.ps1 enumerates schema paths the
    # same way Test-LzSchemaDrift does. Two checks disagreeing about what counts
    # as a path is exactly the drift both exist to prevent.
    'Get-LzSchemaPaths'
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
    'Get-LzSchemaEnum'
    'Get-LzConstraintCounterexample'
    'Test-LzRendererCidrOverlap'
    'New-LzGuardViolation'
)
