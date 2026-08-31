#Requires -Version 7.0
<#
.SYNOPSIS
    Every answer the wizard collects must reach something, or say that it does not.
.DESCRIPTION
    The factory has repeatedly shipped questions whose answers reached nothing:
    the Log Analytics daily quota, whether to deploy a firewall, the policy
    baseline's enforcement mode, the entire ALZ policy surface. Each was found
    by hand, one at a time, and each was the same defect wearing a different
    costume — a client answers a question, the answer is written into
    lz-config.json, and the estate is built as though they had answered
    something else. Nothing fails. That is what makes it expensive.

    This check makes the class structural. Every LEAF key the schema declares
    must be one of:

      * mapped in variable-map.json, so it feeds a Terraform variable;
      * named in a template, factory script, or the wizard's own generated
        markdown, so it reaches a delivered artifact;
      * listed in schema-coverage-register.json as consumed indirectly, naming
        the file that reads it structurally rather than by name;
      * listed in that register as recorded-not-deployed, with a reason and a
        way out, under a budget that only ratchets down.

    The register is a debt ledger, not a suppression list. An entry for a path
    the scanners now find is itself a failure, so an entry cannot quietly
    outlive the gap it describes, and a new question cannot be added without
    either wiring it up or writing down why it is not wired up.
.PARAMETER SchemaPath
    Defaults to factory/schema/lz-config.schema.json.
.PARAMETER RegisterPath
    Defaults to factory/ci/schema-coverage-register.json.
#>
[CmdletBinding()]
param(
    [string]$SchemaPath,
    [string]$MappingPath,
    [string]$RegisterPath,
    [string]$AssetPath,
    [switch]$WriteAsset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $SchemaPath) { $SchemaPath = Join-Path $repo 'factory/schema/lz-config.schema.json' }
if (-not $MappingPath) { $MappingPath = Join-Path $repo 'factory/renderer/variable-map.json' }
if (-not $RegisterPath) { $RegisterPath = Join-Path $repo 'factory/ci/schema-coverage-register.json' }

Import-Module (Join-Path $repo 'factory/renderer/LZFactory.Renderer.psd1') -Force

# ── The leaf set ─────────────────────────────────────────────────────────────
# Get-LzSchemaPaths emits intermediate paths too, so a leaf is a path nothing
# else extends. Shared with Test-LzSchemaDrift deliberately: two checks
# disagreeing about what a path is would be the same drift they exist to catch.
$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json -Depth 40
$allPaths = @()
Get-LzSchemaPaths -Node $schema -Prefix '' -Accumulator ([ref]$allPaths)
$leaves = @($allPaths | Where-Object { -not ($allPaths -like "$_.*") } | Sort-Object)

# ── Consumer 1: the Terraform variable map ───────────────────────────────────
$mapping = Get-Content $MappingPath -Raw | ConvertFrom-Json -Depth 20
$mapped = @()
foreach ($layer in $mapping.layers.PSObject.Properties) {
    $mapped += @($layer.Value.variables.PSObject.Properties.Value)
}
$mapped = @($mapped | Where-Object { $_ -notmatch '^(computed|literal):' } | Sort-Object -Unique)

# ── Consumers 2-4: anything whose CODE names the path ────────────────────────
function Remove-LzSourceComments([string]$Text) {
    # A path named in a comment is not a consumer of it. Documentation prose
    # explaining why an answer goes nowhere would otherwise mark it as going
    # somewhere — the exact inversion this check exists to prevent.
    #
    # Deliberately conservative: block comments, and lines whose first non-space
    # character opens a comment. A trailing comment survives, which can only
    # produce a false PASS on a path that some line of real code also mentions.
    # Over-stripping would fail loudly; under-stripping is the safe direction
    # for the shapes not covered here.
    $text = [regex]::Replace($Text, '(?s)/\*.*?\*/', ' ')
    $text = [regex]::Replace($text, '(?s)<#.*?#>', ' ')
    return [regex]::Replace($text, '(?m)^[ \t]*(?://|#(?!\{\{)).*$', ' ')
}

$corpus = ''
# Templates keep their comments: `#{{IF governance...}}` is a render directive
# that happens to start with a comment marker, and it is real consumption.
foreach ($file in @(Get-ChildItem (Join-Path $repo 'factory/templates') -Recurse -File -Filter '*.tmpl')) {
    $corpus += (Get-Content $file.FullName -Raw) + "`n"
}
# Tests are excluded on purpose: a path only a test mentions reaches no client.
$code = @(Get-ChildItem (Join-Path $repo 'factory'), (Join-Path $repo 'scripts') -Recurse -File -Include '*.ps1', '*.psm1' |
    Where-Object { $_.FullName -notmatch '[/\\]tests[/\\]' })
# site/app.js generates CONFIGURATION.md and NEXT-STEPS.md into the delivered
# answer bundle, which makes the wizard a consumer and not only the collector.
$code += @(Get-Item (Join-Path $repo 'site/app.js'))
foreach ($file in $code) {
    $corpus += (Remove-LzSourceComments (Get-Content $file.FullName -Raw)) + "`n"
}

function Test-LzPathConsumed([string]$Leaf) {
    if ($mapped -contains $Leaf) { return $true }
    # A mapped ancestor covers its children (default_tags feeds naming.defaultTags
    # as a whole); a mapped descendant proves the parent is reached.
    if (@($mapped | Where-Object { $_ -like "$Leaf.*" -or $Leaf -like "$_.*" }).Count -gt 0) { return $true }
    return [bool]($corpus -match [regex]::Escape($Leaf))
}

$uncovered = @($leaves | Where-Object { -not (Test-LzPathConsumed $_) })

# ── The register ─────────────────────────────────────────────────────────────
if (-not (Test-Path $RegisterPath)) {
    Write-Error "No coverage register at $RegisterPath."
    exit 1
}
$register = Get-Content $RegisterPath -Raw | ConvertFrom-Json -Depth 20

$indirect = @{}
foreach ($entry in @($register.consumedIndirectly)) {
    foreach ($path in @($entry.paths)) { $indirect[$path] = $entry }
}
$recorded = @{}
foreach ($entry in @($register.recordedNotDeployed)) {
    foreach ($path in @($entry.paths)) { $recorded[$path] = $entry }
}
$budget = [int]$register.budget

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($path in $uncovered) {
    if ($indirect.ContainsKey($path) -and $recorded.ContainsKey($path)) {
        $failures.Add("DOUBLE-LISTED: '$path' is both consumed-indirectly and recorded-not-deployed. It is one or the other.")
        continue
    }
    if ($indirect.ContainsKey($path) -or $recorded.ContainsKey($path)) { continue }
    $failures.Add("UNCOVERED: '$path' is collected by the wizard and reaches no Terraform variable, no template, no factory script and no generated document. Wire it up, or record it in $(Split-Path $RegisterPath -Leaf) with a reason.")
}

# A register entry for a path the scanners now find is stale: the gap closed and
# the ledger did not notice.
foreach ($path in @($indirect.Keys) + @($recorded.Keys)) {
    if ($path -notin $leaves) {
        $failures.Add("ORPHANED: '$path' is registered but the schema declares no such leaf key. Remove the entry.")
        continue
    }
    if ($path -notin $uncovered) {
        $failures.Add("STALE: '$path' is registered as unconsumed but the coverage scan now finds it. Remove the entry — and lower the budget in the same change if it was recorded-not-deployed.")
    }
}

# An indirect consumer must be a real file that still mentions the key. Without
# this the class is just a second suppression list.
foreach ($entry in @($register.consumedIndirectly)) {
    $consumerPath = Join-Path $repo $entry.consumer
    if (-not (Test-Path $consumerPath)) {
        $failures.Add("MISSING CONSUMER: '$($entry.consumer)' does not exist, but $(@($entry.paths).Count) path(s) claim it reads them.")
        continue
    }
    $consumerText = Get-Content $consumerPath -Raw
    foreach ($path in @($entry.paths)) {
        $segments = @($path -split '\.')
        $leafName = $segments[-1]
        $parentName = if ($segments.Count -gt 1) { $segments[-2] } else { $leafName }
        if ($consumerText -notmatch [regex]::Escape($leafName) -and
            $consumerText -notmatch [regex]::Escape($parentName)) {
            $failures.Add("UNVERIFIABLE CONSUMER: '$($entry.consumer)' mentions neither '$leafName' nor '$parentName', so it cannot be what reads '$path'.")
        }
    }
}

foreach ($entry in @($register.recordedNotDeployed)) {
    if (-not $entry.reason -or -not $entry.resolution) {
        $failures.Add("INCOMPLETE ENTRY: the recorded-not-deployed entry covering [$(@($entry.paths) -join ', ')] must carry both a reason and a resolution. An entry without a way out is a suppression.")
    }
    if (-not $entry.label) {
        $failures.Add("UNLABELLED ENTRY: the recorded-not-deployed entry covering [$(@($entry.paths) -join ', ')] needs a label. The wizard shows it to the client.")
    }
}

# ── The wizard's copy of the ledger ──────────────────────────────────────────
# site/ makes zero network requests by contract, so the wizard cannot read the
# register at runtime — it gets a generated script the same way it gets the ALZ
# policy catalog. Generating it here rather than in a fourth script is what
# keeps the two from disagreeing: the check that decides an answer is
# not-deployed is the same one that tells the wizard to say so.
$assetBody = @(
    '// GENERATED FILE. Do not hand-edit — regenerate with'
    '// factory/ci/Test-SchemaCoverage.ps1 -WriteAsset, whose CI run fails when'
    '// this file and factory/ci/schema-coverage-register.json disagree.'
    '//'
    '// The answers the wizard collects that reach nothing but lz-config.json.'
    '// unmetDependencies() in app.js marks them so the client is told at export'
    '// time, rather than discovering it in the repository they are handed.'
    'globalThis.LZ_RECORDED_NOT_DEPLOYED = ' + (
        @($register.recordedNotDeployed | ForEach-Object {
                [ordered]@{ label = $_.label; module = $_.module; impact = $_.reason; paths = @($_.paths) }
            }) | ConvertTo-Json -Depth 10
    ) + ';'
) -join "`n"

if (-not $AssetPath) { $AssetPath = Join-Path $repo 'site/schema-coverage.js' }
if ($WriteAsset) {
    $assetBody | Set-Content $AssetPath -Encoding utf8
    Write-Host "Wrote $AssetPath (the file the wizard loads)"
}
elseif (-not (Test-Path $AssetPath)) {
    $failures.Add("MISSING ASSET: $AssetPath does not exist. Run factory/ci/Test-SchemaCoverage.ps1 -WriteAsset.")
}
elseif ((Get-Content $AssetPath -Raw).Trim() -ne $assetBody.Trim()) {
    $failures.Add("ASSET DRIFT: $(Split-Path $AssetPath -Leaf) does not match the register. The wizard would tell the client something the ledger no longer says. Run factory/ci/Test-SchemaCoverage.ps1 -WriteAsset.")
}

Write-Host "Schema answer coverage — $(Split-Path $SchemaPath -Leaf)"
Write-Host "  leaf keys declared      : $($leaves.Count)"
Write-Host "  reaching an artifact    : $($leaves.Count - $uncovered.Count)"
Write-Host "  consumed indirectly     : $($indirect.Count)"
Write-Host "  recorded-not-deployed   : $($recorded.Count) (budget $budget)"

# The ratchet. Recorded-not-deployed may only ever shrink, and shrinking it
# means lowering the budget in the same change.
if ($recorded.Count -gt $budget) {
    $failures.Add("BUDGET EXCEEDED: $($recorded.Count) recorded-not-deployed paths against a budget of $budget. The budget only goes down. Wire the answer up instead of widening the ledger.")
}
if ($recorded.Count -lt $budget) {
    $failures.Add("BUDGET NOT TIGHTENED: $($recorded.Count) recorded-not-deployed paths against a budget of $budget. Lower the budget to $($recorded.Count) in the same change that removed the entry, so the ratchet holds.")
}

if ($recorded.Count -gt 0) {
    Write-Host ''
    Write-Host "  NOTE: $($recorded.Count) of $($leaves.Count) answers are collected and not deployed." -ForegroundColor Yellow
    Write-Host '  Each is recorded in lz-config.json and nowhere else. The wizard must' -ForegroundColor Yellow
    Write-Host '  say so wherever it asks — see unmetDependencies() in site/app.js.' -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($f in $failures) { Write-Host "  FAIL $f" }
    Write-Error "$($failures.Count) schema-coverage problem(s). A question whose answer reaches nothing delivers the client an estate other than the one they described, and nothing else in this factory fails when it happens."
    exit 1
}

exit 0
