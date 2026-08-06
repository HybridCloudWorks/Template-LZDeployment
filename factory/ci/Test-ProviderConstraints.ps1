#Requires -Version 7.0
<#
.SYNOPSIS
    Canonical provider version-constraint policy for BOTH Terraform trees.
.DESCRIPTION
    Every `required_providers` entry in terraform/ and
    factory/templates/terraform/ must declare the canonical constraint below,
    unless the file is listed in $EXCEPTIONS with a reason.

    This exists because the same provider constraint is duplicated across ~35
    files spanning root stacks, shared modules, and the customer-facing
    template corpus, while `.github/dependabot.yml` watches only a handful of
    directories and updates one directory per PR. A partial bump is therefore
    the *expected* dependabot outcome, not a freak event — and a partial bump
    between a root stack and a module it calls produces mutually exclusive
    constraints that fail at `terraform init`:

        Error: Failed to query available provider packages
        ... does not match configured version constraint ~> 4.2, ~> 5.0

    That is exactly what dependabot PRs #63-#68 did to `main`: four of five
    live stacks could not initialise, and nothing caught it, because Factory
    CI did not watch terraform/** and the workflows that do watch it fail
    earlier on the missing Azure identity estate.

    This check needs no Azure credentials and no network access, so it runs
    everywhere the rest of Factory CI runs.

    To upgrade a provider: bump $CANONICAL_CONSTRAINTS here AND every
    declaration in both trees, in the same change, and re-lock the affected
    roots.
.NOTES
    Constraint comparison is exact string equality. Two constraints that are
    semantically equivalent but written differently ("~> 4.2" vs ">= 4.2, <
    5.0") are still a finding: divergent spelling across ~35 files is the
    drift this check exists to prevent.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Canonical provider registry ──────────────────────────────────────────────
# One constraint per provider across the entire repository (live + corpus).
$CANONICAL_CONSTRAINTS = [ordered]@{
    'hashicorp/azurerm' = '~> 5.0'
    'hashicorp/random'  = '~> 3.6'
}

# ── Deliberate, reasoned divergences ─────────────────────────────────────────
# A root may pin differently ONLY when it shares no modules with the rest of
# the tree, so it cannot create a constraint conflict. Each entry needs a
# reason; unused entries are reported so this table cannot rot.
$EXCEPTIONS = @()
# ─────────────────────────────────────────────────────────────────────────────

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$roots = @(
    (Join-Path $repo 'terraform'),
    (Join-Path $repo 'factory/templates/terraform')
)

# Parse the `required_providers` blocks of a single file.
# Returns one record per provider entry: local name, source, version, line.
function Get-LzProviderDeclaration {
    param([string]$Path)

    $declarations = @()
    $inRequiredProviders = $false
    $requiredProvidersDepth = 0
    $currentName = $null
    $currentSource = $null
    $currentVersion = $null
    $currentLine = 0
    $lineNumber = 0

    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        $lineNumber++
        $text = ($line -replace '#.*$', '')

        if (-not $inRequiredProviders) {
            if ($text -match '^\s*required_providers\s*\{') {
                $inRequiredProviders = $true
                $requiredProvidersDepth = 1
            }
            continue
        }

        if ($null -eq $currentName) {
            # Between provider entries: watch for the end of required_providers.
            if ($text -match '^\s*(?<name>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*\{') {
                $currentName = $Matches.name
                $currentSource = $null
                $currentVersion = $null
                $currentLine = $lineNumber
                continue
            }
            $requiredProvidersDepth += ([regex]::Matches($text, '\{')).Count
            $requiredProvidersDepth -= ([regex]::Matches($text, '\}')).Count
            if ($requiredProvidersDepth -le 0) { $inRequiredProviders = $false }
            continue
        }

        # Inside a provider entry.
        if ($text -match '^\s*source\s*=\s*"(?<value>[^"]+)"') { $currentSource = $Matches.value }
        if ($text -match '^\s*version\s*=\s*"(?<value>[^"]+)"') { $currentVersion = $Matches.value }

        if ($text -match '\}') {
            $declarations += [pscustomobject]@{
                Name    = $currentName
                Source  = $currentSource
                Version = $currentVersion
                Line    = $currentLine
            }
            $currentName = $null
        }
    }

    return $declarations
}

$findings = @()
$matchedExceptions = @()
$declarationCount = 0

foreach ($root in $roots) {
    if (-not (Test-Path $root -PathType Container)) { throw "Terraform root not found: $root" }

    $files = @(Get-ChildItem $root -Recurse -File |
            Where-Object { $_.Name -like '*.tf' -or $_.Name -like '*.tf.tmpl' } |
            Sort-Object FullName)

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($repo.Length).TrimStart('\', '/').Replace('\', '/')

        foreach ($declaration in @(Get-LzProviderDeclaration -Path $file.FullName)) {
            $declarationCount++

            if ([string]::IsNullOrWhiteSpace($declaration.Source)) {
                $findings += [pscustomobject]@{
                    File = $relativePath; Line = $declaration.Line; Provider = $declaration.Name
                    Declared = '(none)'; Expected = '(a source argument)'
                    Problem  = 'required_providers entry declares no source'
                }
                continue
            }

            if (-not $CANONICAL_CONSTRAINTS.Contains($declaration.Source)) {
                $findings += [pscustomobject]@{
                    File = $relativePath; Line = $declaration.Line; Provider = $declaration.Source
                    Declared = $declaration.Version; Expected = '(registry entry)'
                    Problem  = "Provider is not in the canonical registry - add '$($declaration.Source)' to factory/ci/Test-ProviderConstraints.ps1 `$CANONICAL_CONSTRAINTS"
                }
                continue
            }

            $expected = $CANONICAL_CONSTRAINTS[$declaration.Source]
            $exception = $EXCEPTIONS | Where-Object {
                $_.Path -eq $relativePath -and $_.Provider -eq $declaration.Source
            } | Select-Object -First 1

            if ($exception) {
                $matchedExceptions += $exception
                $expected = $exception.Version
            }

            if ([string]::IsNullOrWhiteSpace($declaration.Version)) {
                $findings += [pscustomobject]@{
                    File = $relativePath; Line = $declaration.Line; Provider = $declaration.Source
                    Declared = '(none)'; Expected = $expected
                    Problem  = 'required_providers entry declares no version constraint'
                }
                continue
            }

            if ($declaration.Version -cne $expected) {
                $problem = if ($exception) {
                    'Constraint differs from the reasoned exception recorded for this file'
                } else {
                    'Constraint differs from the canonical registry entry'
                }
                $findings += [pscustomobject]@{
                    File = $relativePath; Line = $declaration.Line; Provider = $declaration.Source
                    Declared = $declaration.Version; Expected = $expected
                    Problem  = $problem
                }
            }
        }
    }
}

# A stale exception is a latent conflict: it says a divergence is fine for a
# file that no longer declares it.
foreach ($exception in $EXCEPTIONS) {
    if ($matchedExceptions -notcontains $exception) {
        $findings += [pscustomobject]@{
            File = $exception.Path; Line = 0; Provider = $exception.Provider
            Declared = '(declaration not found)'; Expected = $exception.Version
            Problem  = 'Stale entry in $EXCEPTIONS - remove it from factory/ci/Test-ProviderConstraints.ps1'
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Format-List | Out-String | Write-Host
    throw 'Provider version constraints that violate the canonical registry detected.'
}

Write-Host ("Provider constraint policy passed: {0} declaration(s) across both Terraform trees match the canonical registry ({1} provider(s), {2} reasoned exception(s))." -f `
        $declarationCount, $CANONICAL_CONSTRAINTS.Count, $EXCEPTIONS.Count)
