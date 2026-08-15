#Requires -Version 7.0
<#
.SYNOPSIS
    Template-corpus reachability check.
.DESCRIPTION
    Every file under factory/templates/ must be reachable from
    template-manifest.json (files[].source or perLayerFiles[].source), and
    every manifest source must exist. An orphaned template silently ships
    nothing — a client believes a file is part of their repository and it
    never arrives — which is exactly the silent-partial-output failure the
    output contract (docs/refactor/OUTPUT-CONTRACT.md) forbids. Fails CI on
    drift in either direction.

    Static variables.tf files referenced by variable-map.json are also
    manifest sources (copy mode), so no allowlist is needed: the manifest is
    the single source of truth for the corpus.
#>
[CmdletBinding()]
param(
    [string]$TemplateRoot,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $TemplateRoot) { $TemplateRoot = Join-Path $repo 'factory/templates' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $repo 'factory/renderer/template-manifest.json' }

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -Depth 20

$declared = [System.Collections.Generic.HashSet[string]]::new()
foreach ($entry in @($manifest.files) + @($manifest.perLayerFiles)) {
    $null = $declared.Add($entry.source)
}

$problems = @()

# Direction 1: every declared source exists (sentinel sources have no file).
foreach ($source in $declared) {
    if ($source -like '$*') { continue }
    if (-not (Test-Path (Join-Path $TemplateRoot $source))) {
        $problems += "Manifest declares '$source' but no such template exists."
    }
}

# Direction 2: every on-disk template is declared.
$templateRootResolved = (Resolve-Path $TemplateRoot).Path
foreach ($file in @(Get-ChildItem -Path $TemplateRoot -Recurse -File)) {
    $relative = $file.FullName.Substring($templateRootResolved.Length).TrimStart('\', '/') -replace '\\', '/'
    if (-not $declared.Contains($relative)) {
        $problems += "Template '$relative' is not referenced by template-manifest.json — it would silently never ship."
    }
}

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "FAIL $_" }
    Write-Host "$($problems.Count) template-coverage problem(s)."
    exit 1
}

Write-Host "Template coverage: $($declared.Count) manifest sources, all reachable, no orphans."
exit 0
