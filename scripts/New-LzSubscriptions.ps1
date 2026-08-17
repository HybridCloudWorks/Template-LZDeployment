#Requires -Version 7.0

<#
.SYNOPSIS
    Creates the landing-zone subscriptions the wizard planned by name
    (azure.subscriptions.plannedNames) and writes the new subscription IDs
    back into lz-config.json.

.DESCRIPTION
    The wizard's create mode (azure.subscriptions.mode = "create", schema
    2.2.0) exports a configuration whose subscription slots are EMPTY and
    whose plannedNames map carries the convention-derived display names.
    Render guard G25 refuses to render such a configuration, so this script
    is a mandatory step between export and render (ADR 0020).

    What it does, in order:

      1. Loads and structurally validates lz-config.json.
      2. Resolves a billing scope for programmatic subscription creation:
           - Enterprise Agreement:   /billingAccounts/../enrollmentAccounts/..
           - Microsoft Customer Agreement: /billingAccounts/../billingProfiles/../invoiceSections/..
         Mixed estates are supported: every visible billing account is
         enumerated and, when more than one usable scope exists, the
         operator picks one (or passes -BillingScope explicitly).
      3. For every planned slot whose ID slot is still empty, creates the
         subscription via `az account alias create` and polls the alias
         until the subscription ID materialises.
      4. Patches azure.subscriptions.<slot> (and backend.azurerm.subscriptionId,
         if empty, from the management subscription) in lz-config.json, then
         re-validates the file against factory/schema/lz-config.schema.json.

    Plan-first: without -Apply nothing is created and nothing is written —
    the script prints the billing scope it resolved and the subscriptions it
    would create.

    Agreement types that cannot create subscriptions programmatically (CSP,
    pay-as-you-go, sponsorship) are detected as "no usable billing scope":
    create the subscriptions in the portal / Partner Center instead and
    re-run with -Manual to paste the IDs — the same patch-back and
    re-validation applies.

    Authentication comes exclusively from the operator's existing
    `az login` session; no credential is read, stored, or written.

.PARAMETER ConfigPath
    Path to the exported lz-config.json (the file is modified in place on
    -Apply, after a .bak copy is written beside it).

.PARAMETER Apply
    Perform the creation and the config patch-back. Without it the script
    is read-only and prints the plan.

.PARAMETER BillingScope
    Explicit billing scope resource ID to create subscriptions under.
    Skips auto-detection. Use the enrollment-account form for EA or the
    invoice-section form for MCA.

.PARAMETER Manual
    Skip creation entirely: prompt for a subscription ID per planned slot
    (portal-created), then patch and re-validate the config.

.PARAMETER Workload
    Subscription workload type for `az account alias create`:
    Production (default) or DevTest.

.EXAMPLE
    ./scripts/New-LzSubscriptions.ps1 -ConfigPath ./generated-output/exco/lz-config.json

    Plan only: shows the resolved billing scope and the subscriptions that
    would be created.

.EXAMPLE
    ./scripts/New-LzSubscriptions.ps1 -ConfigPath ./generated-output/exco/lz-config.json -Apply

    Creates the subscriptions and writes the IDs back into the config.

.EXAMPLE
    ./scripts/New-LzSubscriptions.ps1 -ConfigPath ./generated-output/exco/lz-config.json -Manual -Apply

    CSP / PAYG path: paste portal-created subscription IDs per slot.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [switch]$Apply,

    [string]$BillingScope,

    [switch]$Manual,

    [ValidateSet('Production', 'DevTest')]
    [string]$Workload = 'Production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

function Write-Info([string]$Message) { Write-Host "  $Message" }
function Write-Section([string]$Message) { Write-Host "`n== $Message" -ForegroundColor Cyan }

function Get-Prop {
    # Strict-mode-safe property read on CLI JSON output.
    param($Object, [Parameter(Mandatory)][string[]]$Path)
    $cursor = $Object
    foreach ($name in $Path) {
        if ($null -eq $cursor) { return $null }
        $prop = $cursor.PSObject.Properties[$name]
        if (-not $prop) { return $null }
        $cursor = $prop.Value
    }
    return $cursor
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $raw = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed (exit $LASTEXITCODE). Are you logged in (az login) with rights on the billing account?"
    }
    if (-not $raw) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-UsableBillingScopes {
    # Returns every scope under which `az account alias create` can be
    # attempted, across EVERY billing account the signed-in operator can see
    # (mixed EA + MCA estates included).
    $scopes = @()
    $accounts = Invoke-Az -Arguments @('billing', 'account', 'list', '--output', 'json') -AllowFailure
    if (-not $accounts) { return $scopes }

    foreach ($acct in $accounts) {
        $type = (Get-Prop $acct @('agreementType')) ?? (Get-Prop $acct @('properties', 'agreementType'))
        if ($type -eq 'EnterpriseAgreement') {
            $enrollments = Invoke-Az -Arguments @(
                'billing', 'enrollment-account', 'list',
                '--billing-account-name', $acct.name, '--output', 'json') -AllowFailure
            foreach ($ea in ($enrollments ?? @())) {
                $scopes += [pscustomobject]@{
                    AgreementType = 'EnterpriseAgreement'
                    Display       = "$($acct.displayName) / enrollment $($ea.name)"
                    Scope         = "/providers/Microsoft.Billing/billingAccounts/$($acct.name)/enrollmentAccounts/$($ea.name)"
                }
            }
        }
        elseif ($type -eq 'MicrosoftCustomerAgreement') {
            $profiles = Invoke-Az -Arguments @(
                'billing', 'profile', 'list',
                '--account-name', $acct.name, '--output', 'json') -AllowFailure
            foreach ($bp in ($profiles ?? @())) {
                $sections = Invoke-Az -Arguments @(
                    'billing', 'invoice', 'section', 'list',
                    '--account-name', $acct.name, '--profile-name', $bp.name, '--output', 'json') -AllowFailure
                foreach ($is in ($sections ?? @())) {
                    $scopes += [pscustomobject]@{
                        AgreementType = 'MicrosoftCustomerAgreement'
                        Display       = "$($acct.displayName) / $($bp.displayName) / $($is.displayName)"
                        Scope         = "/providers/Microsoft.Billing/billingAccounts/$($acct.name)/billingProfiles/$($bp.name)/invoiceSections/$($is.name)"
                    }
                }
            }
        }
        # MicrosoftPartnerAgreement (CSP) and MicrosoftOnlineServicesProgram
        # (PAYG) cannot create subscriptions via the alias API — deliberately
        # not offered; the -Manual path covers them.
    }
    return $scopes
}

function Resolve-BillingScope {
    if ($BillingScope) {
        Write-Info "Using operator-supplied billing scope: $BillingScope"
        return $BillingScope
    }
    Write-Info 'Enumerating billing accounts visible to this az session ...'
    $scopes = @(Get-UsableBillingScopes)
    if ($scopes.Count -eq 0) {
        throw ("No usable billing scope found. Programmatic subscription creation needs an " +
            "Enterprise Agreement enrollment account or an MCA invoice section with " +
            "subscription-creator rights. CSP and pay-as-you-go agreements cannot create " +
            "subscriptions this way: create them in the portal / Partner Center and re-run " +
            "with -Manual to paste the IDs.")
    }
    if ($scopes.Count -eq 1) {
        Write-Info "Billing scope: $($scopes[0].Display) [$($scopes[0].AgreementType)]"
        return $scopes[0].Scope
    }
    Write-Host "`nMore than one usable billing scope is visible:`n"
    for ($i = 0; $i -lt $scopes.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $scopes[$i].Display, $scopes[$i].AgreementType)
    }
    $pick = Read-Host "`nPick a scope [1-$($scopes.Count)]"
    $idx = 0
    if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 1 -or $idx -gt $scopes.Count) {
        throw "Invalid selection '$pick'."
    }
    return $scopes[$idx - 1].Scope
}

function New-AliasSubscription {
    param(
        [Parameter(Mandatory)][string]$AliasName,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Scope
    )
    $existing = Invoke-Az -Arguments @('account', 'alias', 'show', '--name', $AliasName, '--output', 'json') -AllowFailure
    $existingId = Get-Prop $existing @('properties', 'subscriptionId')
    if ($existingId) {
        Write-Info "Alias $AliasName already exists -> $existingId (idempotent re-run)"
        return $existingId
    }
    Write-Info "Creating subscription '$DisplayName' (alias $AliasName) ..."
    $null = Invoke-Az -Arguments @(
        'account', 'alias', 'create',
        '--name', $AliasName,
        '--billing-scope', $Scope,
        '--display-name', $DisplayName,
        '--workload', $Workload,
        '--output', 'json')

    # The alias API is asynchronous: poll until the subscription ID appears.
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 10
        $state = Invoke-Az -Arguments @('account', 'alias', 'show', '--name', $AliasName, '--output', 'json') -AllowFailure
        $subId = Get-Prop $state @('properties', 'subscriptionId')
        if ($subId) {
            Write-Info "  -> $subId"
            return $subId
        }
    } while ((Get-Date) -lt $deadline)
    throw "Alias $AliasName did not produce a subscription ID within 10 minutes. Check 'az account alias show --name $AliasName' and re-run: the script is idempotent."
}

function Read-ManualId([string]$Slot, [string]$PlannedName) {
    while ($true) {
        $id = Read-Host "Subscription ID for '$PlannedName' ($Slot)"
        if ($id -match $script:GuidPattern) { return $id.ToLowerInvariant() }
        Write-Host '  Not a GUID — try again.' -ForegroundColor Yellow
    }
}

# ── Load + sanity-check the configuration ────────────────────────────────────

$ConfigPath = (Resolve-Path -Path $ConfigPath).Path
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable

$subs = $config['azure']?['subscriptions']
if (-not $subs) { throw "Configuration has no azure.subscriptions section: $ConfigPath" }

$mode = $subs['mode'] ?? 'create'
if ($mode -ne 'create') {
    throw "azure.subscriptions.mode is '$mode' — this script only applies to mode=create configurations. Existing-mode configs already carry their subscription IDs."
}

$planned = $subs['plannedNames']
if (-not $planned -or $planned.Count -eq 0) {
    throw 'azure.subscriptions.plannedNames is missing or empty. Re-export the configuration from the wizard with subscription source = create.'
}

$excluded = @($config['deploymentStrategy']?['brownfield']?['excludedSubscriptionIds'] ?? @())

# Deterministic slot order: platform first, then optionals.
$slotOrder = @('management', 'connectivity', 'workloadProd', 'identity', 'workloadNonProd', 'sandbox')
$pending = @()
foreach ($slot in $slotOrder) {
    if (-not $planned.Contains($slot)) { continue }
    $current = [string]($subs[$slot] ?? '')
    if ($current -match $script:GuidPattern) {
        Write-Verbose "Slot $slot already has ID $current — skipping."
        continue
    }
    $pending += [pscustomobject]@{ Slot = $slot; Name = [string]$planned[$slot] }
}

Write-Section "Subscription vending plan — $ConfigPath"
if ($pending.Count -eq 0) {
    Write-Info 'Every planned slot already carries a subscription ID. Nothing to do.'
    return
}
foreach ($p in $pending) { Write-Info ("{0,-16} -> {1}" -f $p.Slot, $p.Name) }

# ── Resolve where the subscriptions come from ────────────────────────────────

$scope = $null
if (-not $Manual) {
    $scope = Resolve-BillingScope
}
else {
    Write-Info 'Manual mode: subscription IDs will be pasted, nothing is created.'
}

if (-not $Apply) {
    Write-Section 'Plan only'
    Write-Info 'No subscription was created and the configuration was not modified.'
    Write-Info 'Re-run with -Apply to create the subscriptions and patch the config.'
    return
}

# ── Create (or collect) and patch back ───────────────────────────────────────

Write-Section 'Creating subscriptions'
$orgShort = [string]($config['organization']?['companyShortName'] ?? 'lz')
$assigned = @{}
foreach ($p in $pending) {
    if ($Manual) {
        $id = Read-ManualId -Slot $p.Slot -PlannedName $p.Name
    }
    else {
        # Alias names must be stable so re-runs are idempotent.
        $alias = ("lz-{0}-{1}" -f $orgShort, $p.Slot).ToLowerInvariant()
        $id = New-AliasSubscription -AliasName $alias -DisplayName $p.Name -Scope $scope
    }
    if ($excluded -contains $id) {
        throw "Subscription $id for slot $($p.Slot) is on the brownfield exclusion list — a subscription cannot be both excluded and part of the new estate (guard G26)."
    }
    $assigned[$p.Slot] = $id
}

Write-Section 'Patching the configuration'
Copy-Item -Path $ConfigPath -Destination "$ConfigPath.bak" -Force
Write-Info "Backup written: $ConfigPath.bak"

foreach ($slot in $assigned.Keys) { $subs[$slot] = $assigned[$slot] }
if (-not [string]($config['backend']?['azurerm']?['subscriptionId'] ?? '') -and $subs['management']) {
    $config['backend']['azurerm']['subscriptionId'] = $subs['management']
    Write-Info "backend.azurerm.subscriptionId <- management subscription ($($subs['management']))"
}

$json = $config | ConvertTo-Json -Depth 32
[System.IO.File]::WriteAllText($ConfigPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
foreach ($slot in $slotOrder) {
    if ($assigned.Contains($slot)) { Write-Info ("{0,-16} = {1}" -f $slot, $assigned[$slot]) }
}

# ── Re-validate against the schema, if it is reachable ───────────────────────

$schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../factory/schema/lz-config.schema.json'
if (Test-Path -Path $schemaPath) {
    Write-Section 'Re-validating the patched configuration'
    $valid = Test-Json -Json (Get-Content -Path $ConfigPath -Raw) -SchemaFile (Resolve-Path $schemaPath).Path -ErrorAction SilentlyContinue
    if ($valid) {
        Write-Info 'lz-config.json validates against the factory schema.'
    }
    else {
        throw "The patched configuration no longer validates against $schemaPath. The pre-patch file is at $ConfigPath.bak."
    }
}
else {
    Write-Info "Schema not found beside this script ($schemaPath) — run the render, it validates the config as gate G00."
}

Write-Section 'Done'
Write-Info 'Continue with discovery, then the bootstrap broker (see NEXT-STEPS.md).'
