#Requires -Version 7.0
<#
.SYNOPSIS
    Every policy default value the pinned ALZ library declares must be supplied
    by the emitted global layer, or explicitly waived.
.DESCRIPTION
    The library declares values its policy assignments need — a DDoS plan ID, a
    Log Analytics workspace ID, the Azure Monitor Agent identity, and so on. If
    an assignment is created and its value is not supplied, the assignment is
    built from the placeholder in the library's own assignment file: a
    security contact of `security_contact@replace_me`, a workspace under
    subscription 00000000-0000-0000-0000-000000000000, a DDoS plan that does
    not exist. Those either fail ARM validation or, worse, are accepted and
    then misbehave at remediation time.

    None of this is visible to any other gate in this factory. The validation
    gate stops at `terraform init -backend=false` and `terraform validate`; the
    end-to-end generation proof stops there too. The ALZ provider resolves
    these values at PLAN time, which nothing here runs. So this check exists to
    catch, statically and without credentials, the one class of defect the rest
    of the pipeline structurally cannot see.

    A default may be unsupplied only if `alz-policy-default-waivers.json` says
    so and says why. That file is a debt register, not a suppression list: a
    waiver for a value that IS supplied is itself a failure, so waivers cannot
    quietly outlive the problem they describe.
.PARAMETER CatalogPath
    The committed catalog. Defaults to site/alz-policy-catalog.json.
#>
[CmdletBinding()]
param(
    [string]$CatalogPath,
    [string]$WaiverPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $CatalogPath) { $CatalogPath = Join-Path $repo 'site/alz-policy-catalog.json' }
if (-not $WaiverPath) { $WaiverPath = Join-Path $repo 'factory/ci/alz-policy-default-waivers.json' }

if (-not (Test-Path $CatalogPath)) {
    Write-Error "No policy catalog at $CatalogPath. Run factory/ci/New-AlzPolicyCatalog.ps1."
    exit 1
}

$catalog = Get-Content $CatalogPath -Raw | ConvertFrom-Json -Depth 20
$globalTemplate = Join-Path $repo 'factory/templates/terraform/live/global/main.tf.tmpl'
$templateText = Get-Content $globalTemplate -Raw

# Read the keys the emitted layer actually supplies. The block is HCL inside a
# template, so this reads the assignment keys rather than parsing HCL properly —
# adequate, because the failure mode we care about is a name that is absent
# entirely, not one that is present but malformed.
$supplied = @()
if ($templateText -match '(?s)policy_default_values\s*=\s*\{(?<body>.*?)\n  \}') {
    $body = $Matches['body']
    $supplied = @([regex]::Matches($body, '(?m)^\s{4}(?<key>[a-z0-9_]+)\s*=') | ForEach-Object { $_.Groups['key'].Value })
}

$waivers = @{}
$waiverBudget = 0
if (Test-Path $WaiverPath) {
    $waiverDoc = Get-Content $WaiverPath -Raw | ConvertFrom-Json -Depth 20
    foreach ($w in @($waiverDoc.waivers)) { $waivers[$w.default] = $w }
    $waiverBudget = [int]$waiverDoc.budget
}

$failures = [System.Collections.Generic.List[string]]::new()
$waived = [System.Collections.Generic.List[string]]::new()

foreach ($name in $catalog.defaults.PSObject.Properties.Name) {
    $consumers = @($catalog.defaults.$name.consumedBy | ForEach-Object { $_.assignment } | Sort-Object -Unique)
    if ($supplied -contains $name) {
        if ($waivers.ContainsKey($name)) {
            $failures.Add("STALE WAIVER: '$name' is waived in $(Split-Path $WaiverPath -Leaf) but the global layer now supplies it. Remove the waiver.")
        }
        continue
    }
    if ($waivers.ContainsKey($name)) {
        $w = $waivers[$name]
        if (-not $w.reason -or -not $w.resolution) {
            $failures.Add("INCOMPLETE WAIVER: '$name' must carry both a reason and a resolution. A waiver without a way out is a suppression.")
        }
        else {
            $waived.Add("$name  [$($consumers -join ', ')]  $($w.reason)")
        }
        continue
    }
    $failures.Add("UNSUPPLIED: '$name' is declared by $($catalog.library.path)@$($catalog.library.ref) and consumed by [$($consumers -join ', ')], but the emitted global layer neither supplies it nor waives it.")
}

foreach ($name in $waivers.Keys) {
    if ($name -notin $catalog.defaults.PSObject.Properties.Name) {
        $failures.Add("ORPHANED WAIVER: '$name' is waived but the library at $($catalog.library.ref) declares no such default value.")
    }
}

Write-Host "ALZ policy default values — $($catalog.library.path)@$($catalog.library.ref)"
Write-Host "  declared by the library : $(@($catalog.defaults.PSObject.Properties.Name).Count)"
Write-Host "  supplied by the layer   : $(@($supplied).Count)$(if (@($supplied).Count) { ' -> ' + ($supplied -join ', ') })"
Write-Host "  waived, with a reason   : $($waived.Count) (budget $waiverBudget)"
foreach ($w in $waived) { Write-Host "      - $w" }

# The ratchet. Waivers may only ever be removed, and removing one means
# decrementing the budget in the same change. Without this the register would
# drift into a place to park new problems.
if ($waivers.Count -gt $waiverBudget) {
    $failures.Add("WAIVER BUDGET EXCEEDED: $($waivers.Count) waivers against a budget of $waiverBudget. The budget only goes down. Supply the value instead of widening the register.")
}
if ($waivers.Count -lt $waiverBudget) {
    $failures.Add("WAIVER BUDGET NOT TIGHTENED: $($waivers.Count) waivers against a budget of $waiverBudget. Lower the budget to $($waivers.Count) in the same change that removed the waiver, so the ratchet holds.")
}

if ($waived.Count -gt 0) {
    Write-Host ''
    Write-Host "  NOTE: $($waived.Count) of $(@($catalog.defaults.PSObject.Properties.Name).Count) policy default values are still unsupplied." -ForegroundColor Yellow
    Write-Host '  Any assignment consuming one of them, if created, is built from the' -ForegroundColor Yellow
    Write-Host "  library's placeholder rather than from this estate's real values." -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($f in $failures) { Write-Host "  $f" }
    Write-Error "$($failures.Count) policy-default problem(s). A default that is neither supplied nor waived produces a policy assignment built from the library's placeholder — an all-zeroes subscription, or security_contact@replace_me."
    exit 1
}

exit 0
