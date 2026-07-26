#Requires -Version 7.0
<#
.SYNOPSIS
    Stage 9 Landing Zone Factory bootstrap broker.
.DESCRIPTION
    Non-interactive entry point. Reads lz-config.json and discovery-inventory.json,
    writes a deterministic plan/audit record, and reconciles external systems only
    when -Apply (or LZ_BOOTSTRAP_APPLY=true) is supplied.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = $(if ($env:LZ_CONFIG_PATH) { $env:LZ_CONFIG_PATH } else { './lz-config.json' }),
    [string]$DiscoveryPath = $(if ($env:LZ_DISCOVERY_PATH) { $env:LZ_DISCOVERY_PATH } else { './discovery-inventory.json' }),
    [string]$OutputDirectory = $(if ($env:LZ_BOOTSTRAP_OUTPUT) { $env:LZ_BOOTSTRAP_OUTPUT } else { './bootstrap-output' }),
    [switch]$Apply,
    [switch]$AllowNotReady
)

$module = Join-Path $PSScriptRoot 'factory/bootstrap/LZFactory.Bootstrap.psm1'
Import-Module $module -Force

$applyRequested = $Apply -or $env:LZ_BOOTSTRAP_APPLY -eq 'true'
Invoke-LzBootstrap -ConfigPath $ConfigPath -DiscoveryPath $DiscoveryPath `
    -OutputDirectory $OutputDirectory -Apply:$applyRequested `
    -AllowNotReady:$AllowNotReady

