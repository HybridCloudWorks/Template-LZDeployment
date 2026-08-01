#Requires -Version 7.0
<#
.SYNOPSIS
    Landing Zone Factory — Phase 0 discovery. Read-only.

.DESCRIPTION
    Standalone entry point for the discovery engine. Imports the module and runs
    a full inventory and readiness assessment against the tenant, GitHub account,
    and Terraform backend named in an lz-config.json.

    Nothing is created, modified, or deleted. This is safe to run against a
    production tenant.

    Outputs, written beside the configuration file:
      tenant-readiness-report.md   Human gate before bootstrap.
      discovery-inventory.json     Machine-readable inventory for later stages.

.PARAMETER ConfigPath
    Path to lz-config.json exported from the wizard (site/index.html).

.PARAMETER OutputDirectory
    Override the artifact destination. Defaults to the configuration's directory.

.PARAMETER SkipDomain
    Skip one or more of: GitHub, Entra, Azure, Terraform.

.PARAMETER FailOnNotReady
    Exit with code 1 when any readiness check fails. Intended for CI.

.EXAMPLE
    ./factory/discovery/Invoke-Discovery.ps1 -ConfigPath ./generated-output/contoso/lz-config.json

.EXAMPLE
    # Assess Azure only, and fail the pipeline if the tenant is not ready.
    ./factory/discovery/Invoke-Discovery.ps1 -ConfigPath ./lz-config.json -SkipDomain GitHub,Terraform -FailOnNotReady
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$OutputDirectory = '',
    [ValidateSet('GitHub', 'Entra', 'Azure', 'Terraform')][string[]]$SkipDomain = @(),
    [switch]$FailOnNotReady,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The status glyphs and box-drawing characters are UTF-8; without this they
# render as replacement characters on a default Windows console.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Cosmetic only: some hosts do not allow changing the console encoding.
    # Write-Debug stays silent unless -Debug is set, so output is unchanged.
    Write-Debug "Could not set console output encoding to UTF-8: $($_.Exception.Message)"
}

Import-Module (Join-Path $PSScriptRoot 'LZFactory.Discovery.psd1') -Force

$discovery = Invoke-LzDiscovery `
    -ConfigPath $ConfigPath `
    -OutputDirectory $OutputDirectory `
    -SkipDomain $SkipDomain `
    -Quiet:$Quiet

if ($FailOnNotReady -and $discovery.Readiness -and -not $discovery.Readiness.Ready) {
    Write-Error "Tenant is not ready: $($discovery.Readiness.FailCount) check(s) failed. See tenant-readiness-report.md."
    exit 1
}

exit 0
