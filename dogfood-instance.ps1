#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Render', 'Plan', 'Apply')][string]$Mode = 'Render',
    [string]$ConfigPath = $env:LZ_DOGFOOD_CONFIG_PATH,
    [string]$OutputDirectory = $env:LZ_DOGFOOD_OUTPUT,
    [string]$EvidenceDirectory = $env:LZ_DOGFOOD_EVIDENCE,
    [string]$Layer = $env:LZ_DOGFOOD_LAYER,
    [switch]$AllowApply
)

& (Join-Path $PSScriptRoot 'factory/dogfood/Invoke-Dogfood.ps1') `
    -Mode $Mode -ConfigPath $ConfigPath -OutputDirectory $OutputDirectory `
    -EvidenceDirectory $EvidenceDirectory -Layer $Layer -AllowApply:$AllowApply
