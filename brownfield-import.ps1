#Requires -Version 7.0
<#
.SYNOPSIS
    Stage 11 brownfield classification and Terraform import generator.
.DESCRIPTION
    Consumes the read-only discovery inventory and an operator-owned
    classification file. Plans by default. Apply writes deterministic import
    blocks/commands into the rendered tree and registers them in
    render-manifest.json; it never executes Terraform import.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = $(if ($env:LZ_CONFIG_PATH) { $env:LZ_CONFIG_PATH } else { './lz-config.json' }),
    [string]$DiscoveryPath = $(if ($env:LZ_DISCOVERY_PATH) { $env:LZ_DISCOVERY_PATH } else { './discovery-inventory.json' }),
    [string]$ClassificationPath = $(if ($env:LZ_BROWNFIELD_CLASSIFICATIONS) { $env:LZ_BROWNFIELD_CLASSIFICATIONS } else { './brownfield-classifications.json' }),
    [string]$RenderedDirectory = $(if ($env:LZ_RENDERED_PATH) { $env:LZ_RENDERED_PATH } else { './rendered-output' }),
    [string]$EvidenceDirectory = $(if ($env:LZ_IMPORT_EVIDENCE) { $env:LZ_IMPORT_EVIDENCE } else { './brownfield-evidence' }),
    [switch]$Apply,
    [switch]$AllowStaleInventory
)

throw @'
brownfield-import is quarantined (docs/refactor/CLASSIFICATION.md, UNRESOLVED-2).
Its import-block generation targets the retired bespoke module resource
addresses; the emitted architecture now references Azure Verified Modules,
whose internal resource addresses differ. Re-targeting requires verifying
those addresses against the pinned module versions. Track ADR 0013.
'@

$module = Join-Path $PSScriptRoot 'factory/import/LZFactory.Import.psm1'
Import-Module $module -Force

$applyRequested = $Apply -or $env:LZ_IMPORT_APPLY -eq 'true'
$allowStale = $AllowStaleInventory -or $env:LZ_IMPORT_ALLOW_STALE -eq 'true'

Invoke-LzBrownfieldImport -ConfigPath $ConfigPath -DiscoveryPath $DiscoveryPath `
    -ClassificationPath $ClassificationPath -RenderedDirectory $RenderedDirectory `
    -EvidenceDirectory $EvidenceDirectory -Apply:$applyRequested `
    -AllowStaleInventory:$allowStale
