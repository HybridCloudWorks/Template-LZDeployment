#Requires -Version 7.0
<#
.SYNOPSIS
    Post-render validation gate.
.DESCRIPTION
    Verifies the rendered tree is deployable before the scaffold publishes it:
    inventory integrity, terraform fmt/init/validate, workflow SHA pinning,
    provider-constraint consistency, lint, and security scanning. Read-only
    against the rendered tree except terraform init's .terraform directories,
    which are confined to a temporary scratch copy that is deleted afterwards,
    so the rendered tree stays byte-identical for the scaffold's inventory
    verification. All values are provided by parameters or environment
    variables; this entry point never prompts.
#>
[CmdletBinding()]
param(
    [string]$RenderedDirectory = $(if ($env:LZ_RENDERED_PATH) { $env:LZ_RENDERED_PATH } else { './rendered-output' }),
    [string]$EvidenceDirectory = $(if ($env:LZ_VALIDATE_EVIDENCE) { $env:LZ_VALIDATE_EVIDENCE } else { './validate-evidence' }),
    [switch]$Strict,
    [switch]$SkipSecurityScan,
    [switch]$SkipLint
)

$module = Join-Path $PSScriptRoot 'factory/validate/LZFactory.Validate.psm1'
Import-Module $module -Force

$strictRequested = $Strict -or $env:LZ_VALIDATE_STRICT -eq 'true'
$skipSecurityScanRequested = $SkipSecurityScan -or $env:LZ_VALIDATE_SKIP_SECURITY_SCAN -eq 'true'
$skipLintRequested = $SkipLint -or $env:LZ_VALIDATE_SKIP_LINT -eq 'true'

Invoke-LzValidate -RenderedDirectory $RenderedDirectory -EvidenceDirectory $EvidenceDirectory `
    -Strict:$strictRequested -SkipSecurityScan:$skipSecurityScanRequested `
    -SkipLint:$skipLintRequested
