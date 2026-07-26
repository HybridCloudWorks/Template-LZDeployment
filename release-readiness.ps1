#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$FactoryCiReport = $env:LZ_RELEASE_FACTORY_CI_REPORT,
    [string]$DogfoodReport = $env:LZ_RELEASE_DOGFOOD_REPORT,
    [string]$AttestationPath = $env:LZ_RELEASE_ATTESTATION_PATH,
    [string]$OutputDirectory = $env:LZ_RELEASE_EVIDENCE,
    [switch]$AllowIncomplete
)

& (Join-Path $PSScriptRoot 'factory/release/Invoke-ReleaseReadiness.ps1') `
    -FactoryCiReport $FactoryCiReport -DogfoodReport $DogfoodReport `
    -AttestationPath $AttestationPath -OutputDirectory $OutputDirectory `
    -AllowIncomplete:$AllowIncomplete
