#Requires -Version 7.0
<#
.SYNOPSIS
    Every module README's Variables table must match the module's variables.tf.
.DESCRIPTION
    Each `terraform/modules/*/README.md` documents the module's inputs in a
    `## Variables` table. Nothing enforced that it stayed true as modules
    changed, so it drifted: five of eleven modules had no Variables section at
    all while declaring 41 variables between them.

    A wrong or absent variable table is not cosmetic here. These READMEs are
    the interface documentation a customer reads for a module shipped into
    their generated repository, and the corpus copy travels with it.

    Checked in both directions, because both fail differently:

      Undocumented variable — an input nobody knows exists. Symptom: an
                              operator cannot discover a required setting
                              without reading HCL.
      Stale documented row  — a variable that no longer exists. Symptom: an
                              operator sets something that is silently ignored.

    Modules that declare no variables are exempt from needing a section.
.NOTES
    Scoped to variable NAMES on purpose. Prose, types and defaults are not
    diffed: a check that fails on a reworded description trains people to
    ignore it. Names are the part that silently rots.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $repo 'factory/renderer/LZFactory.Renderer.psd1') -Force

$roots = @(
    (Join-Path $repo 'terraform/modules'),
    (Join-Path $repo 'factory/templates/terraform/modules')
)

function Get-LzDocumentedVariable {
    <#
    .SYNOPSIS
        Variable names listed in a README's `## Variables` table.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return @() }

    $names = @()
    $inVariables = $false
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        # Any heading ends the section; only a Variables heading starts it.
        if ($line -match '^#{2,}\s') {
            $inVariables = [bool]($line -match '^#{2,}\s+Variables\s*$')
            continue
        }
        if ($inVariables -and $line -match '^\|\s*`([a-z0-9_]+)`') {
            $names += $Matches[1]
        }
    }
    return $names
}

$findings = @()
$checked = 0

foreach ($root in $roots) {
    if (-not (Test-Path $root -PathType Container)) { throw "Module root not found: $root" }

    foreach ($module in @(Get-ChildItem $root -Directory | Sort-Object Name)) {
        $relative = $module.FullName.Substring($repo.Length).TrimStart('\', '/').Replace('\', '/')
        $variablesFile = Join-Path $module.FullName 'variables.tf'
        $readmeFile = Join-Path $module.FullName 'README.md'

        $declared = @(Get-LzTerraformVariables -Path $variablesFile | ForEach-Object { $_.Name })
        if ($declared.Count -eq 0) { continue }
        $checked++

        if (-not (Test-Path $readmeFile)) {
            $findings += [pscustomobject]@{
                Module = $relative; Problem = 'Module declares variables but has no README.md'
                Detail = "$($declared.Count) variable(s) undocumented"
            }
            continue
        }

        $documented = @(Get-LzDocumentedVariable -Path $readmeFile)
        if ($documented.Count -eq 0) {
            $findings += [pscustomobject]@{
                Module = $relative; Problem = 'README.md has no "## Variables" section'
                Detail = "$($declared.Count) declared variable(s): $($declared -join ', ')"
            }
            continue
        }

        $undocumented = @($declared | Where-Object { $_ -notin $documented })
        $stale = @($documented | Where-Object { $_ -notin $declared })

        if ($undocumented.Count -gt 0) {
            $findings += [pscustomobject]@{
                Module = $relative; Problem = 'Declared variable(s) missing from the README table'
                Detail = ($undocumented -join ', ')
            }
        }
        if ($stale.Count -gt 0) {
            $findings += [pscustomobject]@{
                Module = $relative; Problem = 'README table documents variable(s) that no longer exist'
                Detail = ($stale -join ', ')
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Format-List | Out-String | Write-Host
    throw 'Module README variable tables are out of sync with variables.tf.'
}

Write-Host ("Module docs policy passed: {0} module README(s) across both trees match their variables.tf." -f $checked)
