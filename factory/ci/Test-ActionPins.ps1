#Requires -Version 7.0
<#
.SYNOPSIS
    Canonical-SHA action pinning policy for BOTH workflow trees.
.DESCRIPTION
    Every `uses:` reference in .github/workflows/ and
    factory/templates/.github/workflows/ must match the canonical registry
    below EXACTLY — same action, same commit SHA. This replaces the old
    "any 40-hex SHA" rule, under which the corpus templates silently fell a
    whole action generation behind live (corpus-live-reconciliation plan,
    finding (b)): pin DRIFT could never fail CI, only pin ABSENCE.

    To upgrade an action: bump the SHA here AND in every workflow that uses
    it, in the same change. Dependabot bumps must update both.
.NOTES
    Local composite actions (./...) and docker:// references are exempt.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Canonical action registry ────────────────────────────────────────────────
# One SHA per action across the entire repository (live + corpus templates).
$CANONICAL_PINS = [ordered]@{
    'actions/checkout'                  = @{ sha = '3d3c42e5aac5ba805825da76410c181273ba90b1'; version = 'v7.0.1' }
    'actions/configure-pages'           = @{ sha = '45bfe0192ca1faeb007ade9deae92b16b8254a0d'; version = 'v6.0.0' }
    'actions/dependency-review-action'  = @{ sha = 'a1d282b36b6f3519aa1f3fc636f609c47dddb294'; version = 'v5.0.0' }
    'actions/deploy-pages'              = @{ sha = 'cd2ce8fcbc39b97be8ca5fce6e763baed58fa128'; version = 'v5.0.0' }
    'actions/download-artifact'         = @{ sha = '3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c'; version = 'v8.0.1' }
    'actions/github-script'             = @{ sha = '3a2844b7e9c422d3c10d287c895573f7108da1b3'; version = 'v9.0.0' }
    'actions/upload-artifact'           = @{ sha = '043fb46d1a93c77aae656e7c1c64a875d1fc6a0a'; version = 'v7.0.1' }
    'actions/upload-pages-artifact'     = @{ sha = 'fc324d3547104276b827a68afc52ff2a11cc49c9'; version = 'v5.0.0' }
    'azure/login'                       = @{ sha = 'f5d393ae46f8fde4be8b75f32e3fc50e654ad0ca'; version = 'v3.0.1' }
    'hashicorp/setup-terraform'         = @{ sha = 'dfe3c3f87815947d99a8997f908cb6525fc44e9e'; version = 'v4.0.1' }
    'terraform-linters/setup-tflint'    = @{ sha = '6e1e0642c0289bd619021bf6b34e3c08ed1e005a'; version = 'v6.3.0' }
    # v3.97.1 tag SHA verified against the upstream repo (git ls-remote) after
    # the Dependabot bump in #124, which superseded the #100 bump to v3.97.0.
    'trufflesecurity/trufflehog'        = @{ sha = '20652fbbdefffcdaa493a5bf57ab2ac6b1db715b'; version = 'v3.97.1' }
}
# ─────────────────────────────────────────────────────────────────────────────

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$roots = @(
    (Join-Path $repo '.github/workflows'),
    (Join-Path $repo 'factory/templates/.github/workflows')
)
$findings = @()
foreach ($root in $roots) {
    foreach ($file in @(Get-ChildItem $root -Recurse -File -Include *.yml,*.yaml,*.tmpl)) {
        $lineNumber = 0
        foreach ($line in @(Get-Content $file.FullName)) {
            $lineNumber++
            if ($line -notmatch '^\s*uses:\s*(?<reference>[^\s#]+)') { continue }
            $reference = $Matches.reference
            if ($reference.StartsWith('./') -or $reference.StartsWith('docker://')) { continue }

            $relativePath = $file.FullName.Substring($repo.Length).TrimStart('\', '/')

            if ($reference -notmatch '^(?<action>[^@]+)@(?<ref>.+)$') {
                $findings += [pscustomobject]@{
                    file = $relativePath; line = $lineNumber; reference = $reference
                    problem = 'Unparseable action reference (expected <action>@<sha>)'
                    canonical = ''
                }
                continue
            }
            $action = $Matches.action
            $pinnedRef = $Matches.ref

            if (-not $CANONICAL_PINS.Contains($action)) {
                $findings += [pscustomobject]@{
                    file = $relativePath; line = $lineNumber; reference = $reference
                    problem = 'Action is not in the canonical registry'
                    canonical = "add '$action' to factory/ci/Test-ActionPins.ps1 `$CANONICAL_PINS with its full commit SHA"
                }
                continue
            }

            $canonicalEntry = $CANONICAL_PINS[$action]
            if ($pinnedRef -cne $canonicalEntry.sha) {
                $problem = if ($pinnedRef -notmatch '^[0-9a-fA-F]{40}$') {
                    'Not pinned to a full commit SHA'
                } else {
                    'SHA differs from the canonical registry entry'
                }
                $findings += [pscustomobject]@{
                    file = $relativePath; line = $lineNumber; reference = $reference
                    problem = $problem
                    canonical = "$action@$($canonicalEntry.sha) # $($canonicalEntry.version)"
                }
            }
        }
    }
}
if ($findings.Count -gt 0) {
    $findings | Format-List | Out-String | Write-Host

    # A Dependabot bump changes the workflow and never the registry, so this
    # check fails on every one of them and the remediation is the same two
    # steps each time. Spelling them out is the difference between a five-minute
    # fix and a rediscovery — #100 and #124 both cost the latter.
    $stale = @($findings | Where-Object { $_.problem -eq 'SHA differs from the canonical registry entry' })
    if ($stale.Count -gt 0) {
        Write-Host 'This is the shape a Dependabot action bump leaves behind: the workflow moved, the registry did not.'
        Write-Host 'Update BOTH IN ONE COMMIT — a registry change ahead of the workflow change fails this check on main itself.'
        Write-Host ''
        foreach ($reference in @($stale | ForEach-Object { $_.reference } | Sort-Object -Unique)) {
            $action = ($reference -split '@')[0]
            $sha = ($reference -split '@')[1]
            Write-Host "  1. Verify the new SHA is the tag it claims:"
            Write-Host "       git ls-remote --tags https://github.com/$action | grep $sha"
            Write-Host "  2. Set it in the `$CANONICAL_PINS entry for '$action' in $(Split-Path $PSCommandPath -Leaf):"
            Write-Host "       '$action' = @{ sha = '$sha'; version = '<the tag from step 1>' }"
            Write-Host ''
        }
    }

    throw 'Action references that violate the canonical-SHA registry detected.'
}
Write-Host ("Action pinning policy passed: every reference matches the canonical registry ({0} actions)." -f $CANONICAL_PINS.Count)
