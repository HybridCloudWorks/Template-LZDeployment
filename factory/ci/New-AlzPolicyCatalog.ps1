#Requires -Version 7.0
<#
.SYNOPSIS
    Generate (or verify) the ALZ policy catalog the wizard offers to clients.
.DESCRIPTION
    The pinned Azure Landing Zones library is the authority on three things
    this factory cannot invent: which policy assignments exist, which
    management-group archetype each one attaches to, and which "policy default
    values" each one needs supplied before it can be created.

    `site/` is zero-network by construction (CSP connect-src 'none', enforced by
    Test-SiteNoNetwork.ps1), so the wizard cannot read the library at runtime.
    This script reads it at BUILD time, at exactly the ref recorded in
    factory-version.json, and writes the answer to a committed JSON file the
    wizard loads as a static asset.

    Two modes:

      (default)  Regenerate site/alz-policy-catalog.json.
      -Verify    Regenerate in memory and compare. Non-zero exit on drift, so
                 a library bump that is not accompanied by a regenerated
                 catalog fails CI instead of shipping a wizard that offers
                 policies the library no longer defines — or, worse, silently
                 omits ones it now does.

    Offline behaviour is deliberate. With -AllowOffline, an unreachable library
    is reported as a skip rather than a failure, matching how the validation
    gate treats a missing tflint. A skip is evidence, not a pass.
.PARAMETER CatalogPath
    Output (or comparison) path. Defaults to site/alz-policy-catalog.json.
.PARAMETER Verify
    Compare instead of write. Exit 1 on drift.
.PARAMETER AllowOffline
    Exit 0 with a recorded skip when the library cannot be fetched.
.PARAMETER LibraryRoot
    Read the library from a local directory instead of fetching it. Used by the
    tests so they never depend on network access.
#>
[CmdletBinding()]
param(
    [string]$CatalogPath,
    [switch]$Verify,
    [switch]$AllowOffline,
    [string]$LibraryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $CatalogPath) { $CatalogPath = Join-Path $repo 'site/alz-policy-catalog.json' }

$factoryVersion = Get-Content (Join-Path $repo 'factory-version.json') -Raw | ConvertFrom-Json -Depth 20
$libraryPath = $factoryVersion.avm.alzLibrary.path
$libraryRef = $factoryVersion.avm.alzLibrary.ref

# The archetype set is itself declared by the architecture definition, so the
# only name hard-coded here is the architecture's own.
$architectureName = 'alz'

# ── Capability groups ────────────────────────────────────────────────────────
# The library ships ~80 assignments. Eighty checkboxes is not a decision a
# client can make; these are the groupings a platform team actually reasons in.
# Every assignment the map does not name falls into 'advanced' and is offered
# individually, so a library bump can add policies without this file silently
# swallowing them.
$groupMap = [ordered]@{
    'ddos' = @{
        label = 'DDoS network protection'
        summary = 'Attaches an Azure DDoS Network Protection plan to every virtual network. The plan itself is roughly USD 2,900/month and is NOT created by this factory — enabling this group requires an existing plan ID.'
        assignments = @('Enable-DDoS-VNET')
    }
    'defender' = @{
        label = 'Microsoft Defender for Cloud'
        summary = 'Defender plans, security contact, and the Defender-for-SQL agent estate. Every plan parameter defaults to Disabled in the library, so enabling this group costs nothing until plans are turned on.'
        assignments = @('Deploy-MDFC-Config-H224', 'Deploy-MDFC-DefSQL-AMA', 'Deploy-MDFC-OssDb',
            'Deploy-MDFC-SqlAtp', 'Deploy-MDEndpoints', 'Deploy-MDEndpointsAMA',
            'Deploy-ASC-Monitoring', 'Deploy-MCSB2-Monitoring')
    }
    'vm-monitoring' = @{
        label = 'VM monitoring, change tracking and updates'
        summary = 'Azure Monitor Agent, VM Insights, change tracking and update management. Needs the managed identity and data collection rules the management layer creates.'
        assignments = @('Deploy-VM-Monitoring', 'Deploy-VMSS-Monitoring', 'Deploy-vmHybr-Monitoring',
            'Deploy-VM-ChangeTrack', 'Deploy-VMSS-ChangeTrack', 'Deploy-vmArc-ChangeTrack',
            'DenyAction-DeleteUAMIAMA', 'Deploy-GuestAttest', 'Enable-AUM-CheckUpdates')
    }
    'private-dns' = @{
        label = 'Private DNS zones for private endpoints'
        summary = 'Central private DNS zone records for private endpoints, created in the connectivity subscription.'
        assignments = @('Deploy-Private-DNS-Zones', 'Audit-PeDnsZones')
    }
    'service-health' = @{
        label = 'Service health alerts'
        summary = 'Azure Service Health alert rules and their action group.'
        assignments = @('Deploy-SvcHealth-BuiltIn')
    }
    'platform-diagnostics' = @{
        label = 'Platform diagnostic settings'
        summary = 'Routes activity logs and resource diagnostics to the platform Log Analytics workspace. Additive: it does not replace diagnostic settings a resource already has.'
        assignments = @('Deploy-AzActivity-Log', 'Deploy-Diag-LogsCat', 'Deploy-AzSqlDb-Auditing')
    }
    'network-restrictions' = @{
        label = 'Network restrictions'
        summary = 'Denies public endpoints, public IPs on NICs, management ports open to the internet, subnets without an NSG, and hybrid networking. The sharpest group in the set for an estate with public-facing services.'
        assignments = @('Deny-Public-Endpoints', 'Deny-Public-IP', 'Deny-Public-IP-On-NIC',
            'Deny-HybridNetworking', 'Deny-IP-forwarding', 'Deny-MgmtPorts-Internet',
            'Deny-Subnet-Without-Nsg', 'Enforce-Subnet-Private')
    }
    'service-guardrails' = @{
        label = 'Per-service guardrails'
        summary = 'The Enforce-GR-* family: per-service hardening initiatives for storage, Key Vault, SQL, Kubernetes, OpenAI and the rest. Most ship with enforcement disarmed in the library.'
        assignments = @()   # populated by prefix below
        prefixes = @('Enforce-GR-')
    }
    'data-protection' = @{
        label = 'Data protection and encryption'
        summary = 'Transparent data encryption, SQL threat detection, VM backup, site recovery, customer-managed keys, and TLS/HTTPS enforcement.'
        assignments = @('Deploy-SQL-TDE', 'Deploy-SQL-Threat', 'Deploy-VM-Backup', 'Enforce-ASR',
            'Enforce-Encrypt-CMK0', 'Deny-Storage-http', 'Enforce-TLS-SSL-Q225', 'Enforce-AKS-HTTPS')
    }
    'aks-hardening' = @{
        label = 'Kubernetes hardening'
        summary = 'Denies privileged and privilege-escalating containers in AKS.'
        assignments = @('Deny-Priv-Esc-AKS', 'Deny-Privileged-AKS')
    }
    'resource-hygiene' = @{
        label = 'Resource hygiene and audit'
        summary = 'Audit-only checks plus bans on classic and unmanaged-disk resources. Cheap to leave on: these report, they do not block.'
        assignments = @('Audit-UnusedResources', 'Audit-ResourceRGLocation', 'Audit-ZoneResiliency',
            'Audit-TrustedLaunch', 'Audit-AppGW-WAF', 'Deny-Classic-Resources',
            'Deny-UnmanagedDisk', 'Enforce-ACSB', 'Enforce-ALDO-Services')
    }
    'mg-lifecycle' = @{
        label = 'Sandbox and decommissioned guardrails'
        summary = 'The lifecycle guardrails attached to the sandbox and decommissioned management groups.'
        assignments = @('Enforce-ALZ-Sandbox', 'Enforce-ALZ-Decomm')
    }
}

function Get-LzLibraryFile {
    param([Parameter(Mandatory)][string]$RelativePath)

    if ($LibraryRoot) {
        $local = Join-Path $LibraryRoot $RelativePath
        if (-not (Test-Path $local)) { throw "Library file not found under -LibraryRoot: $RelativePath" }
        return Get-Content $local -Raw
    }

    $uri = "https://raw.githubusercontent.com/Azure/Azure-Landing-Zones-Library/$libraryPath/$libraryRef/$libraryPath/$RelativePath"
    $params = @{ Uri = $uri; UseBasicParsing = $true; TimeoutSec = 60; ErrorAction = 'Stop' }
    # Honour an explicit egress proxy when one is configured; PowerShell does
    # not always pick it up from the environment on its own.
    $proxy = $env:HTTPS_PROXY; if (-not $proxy) { $proxy = $env:https_proxy }
    if ($proxy) { $params['Proxy'] = $proxy }
    return (Invoke-WebRequest @params).Content
}

function New-LzPolicyCatalog {
    $architecture = Get-LzLibraryFile "architecture_definitions/$architectureName.alz_architecture_definition.json" | ConvertFrom-Json -Depth 20

    # The architecture definition is a FLAT list carrying a parent_id edge, not
    # a nested tree — worth stating, because reading it as nested yields a
    # plausible-looking hierarchy in which everything is a child of the tenant
    # root. The same shape is what a custom architecture definition has to use.
    $managementGroups = [System.Collections.Generic.List[object]]::new()
    foreach ($mg in $architecture.management_groups) {
        $parent = if ($null -eq $mg.parent_id) { '' } else { [string]$mg.parent_id }
        $managementGroups.Add([ordered]@{
                id          = $mg.id
                displayName = $mg.display_name
                parent      = $parent
                archetypes  = @($mg.archetypes)
            })
    }

    # Archetype -> assignments.
    $archetypeNames = @($managementGroups | ForEach-Object { $_.archetypes } | Where-Object { $_ } | Sort-Object -Unique)
    $archetypes = [ordered]@{}
    foreach ($name in $archetypeNames) {
        $definition = Get-LzLibraryFile "archetype_definitions/$name.alz_archetype_definition.json" | ConvertFrom-Json -Depth 20
        $archetypes[$name] = @(@($definition.policy_assignments) | Where-Object { $_ } | Sort-Object)
    }

    # Default value -> the assignments and parameters that consume it. This is
    # the edge that matters: it is what turns "the library needs 14 values" into
    # "you selected DDoS, so you owe a plan ID".
    $defaultsDoc = Get-LzLibraryFile 'alz_policy_default_values.json' | ConvertFrom-Json -Depth 20
    $defaults = [ordered]@{}
    $assignmentDefaults = @{}
    foreach ($entry in $defaultsDoc.defaults) {
        $consumers = [System.Collections.Generic.List[object]]::new()
        foreach ($pa in @($entry.policy_assignments)) {
            $consumers.Add([ordered]@{
                    assignment = $pa.policy_assignment_name
                    parameters = @($pa.parameter_names)
                })

            if (-not $assignmentDefaults.ContainsKey($pa.policy_assignment_name)) {
                $assignmentDefaults[$pa.policy_assignment_name] = [System.Collections.Generic.List[string]]::new()
            }
            if ($assignmentDefaults[$pa.policy_assignment_name] -notcontains $entry.default_name) {
                $assignmentDefaults[$pa.policy_assignment_name].Add($entry.default_name)
            }
        }
        $defaults[$entry.default_name] = [ordered]@{
            description = $entry.description
            consumedBy  = @($consumers)
        }
    }

    # Who owes each value. The wizard prompts for a default only when the
    # factory does not already compute it, so this classification has to be
    # read from the emitted layer rather than restated in JavaScript:
    #
    #   factory  the global template composes it from platform facts (remote
    #            state, the region, the org prefix) — no client answer exists
    #            or is wanted.
    #   client   the template emits it from a variable that variable-map.json
    #            feeds out of governance.policySelection.values — the client
    #            must answer, and the wizard is where they do.
    #   none     nothing supplies it yet. Same prompt as 'client', so closing
    #            the gap in the template cannot silently remove the question.
    #
    # Deriving 'client' from the variable map rather than from the template
    # alone is what keeps this non-circular: an answer-fed value stays a
    # question after the template starts emitting it.
    $globalTemplate = Get-Content (Join-Path $repo 'factory/templates/terraform/live/global/main.tf.tmpl') -Raw
    $emitted = @()
    if ($globalTemplate -match '(?s)policy_default_values\s*=\s*\{(?<body>.*?)\n  \}') {
        $emitted = @([regex]::Matches($Matches['body'], '(?m)^\s{4}(?<key>[a-z0-9_]+)\s*=') |
            ForEach-Object { $_.Groups['key'].Value })
    }
    $variableMap = Get-Content (Join-Path $repo 'factory/renderer/variable-map.json') -Raw | ConvertFrom-Json -Depth 20
    $clientFed = @($variableMap.layers.global.variables.PSObject.Properties |
        Where-Object { "$($_.Value)".StartsWith('governance.policySelection.values.') } |
        ForEach-Object { $_.Name })
    foreach ($name in @($defaults.Keys)) {
        $defaults[$name].supplied =
        if ($clientFed -contains $name) { 'client' }
        elseif ($emitted -contains $name) { 'factory' }
        else { 'none' }
    }

    # Assignment -> the archetypes that carry it and the defaults it needs.
    $allAssignments = @($archetypes.Values | ForEach-Object { $_ } | Sort-Object -Unique)
    $assignments = [ordered]@{}
    foreach ($name in $allAssignments) {
        $carriedBy = @($archetypes.Keys | Where-Object { $archetypes[$_] -contains $name } | Sort-Object)
        $needs = if ($assignmentDefaults.ContainsKey($name)) { @($assignmentDefaults[$name] | Sort-Object) } else { @() }
        # Which management groups actually carry this policy, resolved through
        # the archetype. This is the form a client can reason about: "corp and
        # everything under it", not "the corp archetype".
        $onGroups = @($managementGroups | Where-Object { $mgArchetypes = @($_.archetypes); @($carriedBy | Where-Object { $mgArchetypes -contains $_ }).Count -gt 0 } | ForEach-Object { $_.id } | Sort-Object)
        $assignments[$name] = [ordered]@{
            archetypes       = @($carriedBy)
            managementGroups = @($onGroups)
            requiredDefaults = @($needs)
        }
    }

    # Groups. Anything the curated map does not claim is offered individually
    # rather than dropped — a library bump must never silently remove a client's
    # ability to see a policy.
    $claimed = [System.Collections.Generic.HashSet[string]]::new()
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $groupMap.Keys) {
        $spec = $groupMap[$id]
        $members = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($spec.assignments)) {
            if ($allAssignments -contains $name) { [void]$members.Add($name) }
        }
        if ($spec.ContainsKey('prefixes')) {
            foreach ($prefix in $spec.prefixes) {
                foreach ($name in $allAssignments) {
                    if ($name.StartsWith($prefix) -and $members -notcontains $name) { [void]$members.Add($name) }
                }
            }
        }
        foreach ($name in $members) { [void]$claimed.Add($name) }
        $needs = @($members | ForEach-Object { $assignments[$_].requiredDefaults } | Where-Object { $_ } | Sort-Object -Unique)
        $groups.Add([ordered]@{
                id               = $id
                label            = $spec.label
                summary          = $spec.summary
                assignments      = @($members | Sort-Object)
                requiredDefaults = @($needs)
            })
    }
    $ungrouped = @($allAssignments | Where-Object { -not $claimed.Contains($_) } | Sort-Object)

    return [ordered]@{
        '$comment'       = 'GENERATED FILE. Do not hand-edit. Produced by factory/ci/New-AlzPolicyCatalog.ps1 from the Azure Landing Zones library at the ref pinned in factory-version.json. The wizard reads this as a static asset because site/ makes zero network requests by contract.'
        catalogVersion   = '1.0.0'
        library          = [ordered]@{
            path         = $libraryPath
            ref          = $libraryRef
            architecture = $architectureName
        }
        managementGroups = @($managementGroups)
        archetypes       = $archetypes
        defaults         = $defaults
        assignments      = $assignments
        groups           = @($groups)
        ungrouped        = $ungrouped
    }
}

try {
    $catalog = New-LzPolicyCatalog
}
catch {
    if ($AllowOffline) {
        Write-Host "SKIPPED: the pinned ALZ library could not be read ($($_.Exception.Message))."
        Write-Host 'A skip is not a pass: re-run where raw.githubusercontent.com is reachable before relying on this check.'
        exit 0
    }
    throw
}

$json = ($catalog | ConvertTo-Json -Depth 20)

# The wizard cannot read the JSON. site/index.html sets
# `connect-src 'none'` and factory/ci/Test-SiteNoNetwork.ps1 bans fetch and
# XMLHttpRequest, so there is no way to load a .json at runtime. `script-src
# 'self'` does permit a second same-origin script, so the same catalog is also
# emitted as a .js file that assigns a global. Both are generated, both are
# verified; hand-editing either is what the -Verify mode exists to catch.
$scriptPath = [IO.Path]::ChangeExtension($CatalogPath, 'js')
$scriptBody = @"
// GENERATED FILE. Do not hand-edit — regenerate with
// factory/ci/New-AlzPolicyCatalog.ps1, which emits this alongside
// alz-policy-catalog.json from the ALZ library ref pinned in
// factory-version.json.
//
// This exists because the wizard is zero-network by contract: the page's
// Content-Security-Policy sets connect-src 'none', so the .json sibling cannot
// be fetched at runtime. A same-origin script is allowed, so the catalog
// arrives as a global instead.
globalThis.ALZ_POLICY_CATALOG = $json;
"@

if ($Verify) {
    if (-not (Test-Path $CatalogPath)) {
        Write-Error "No catalog at $CatalogPath. Run factory/ci/New-AlzPolicyCatalog.ps1 to generate it."
        exit 1
    }
    if (-not (Test-Path $scriptPath)) {
        Write-Error "No catalog script at $scriptPath. Run factory/ci/New-AlzPolicyCatalog.ps1 to generate it. The wizard loads this file, not the JSON."
        exit 1
    }
    $committedScript = (Get-Content $scriptPath -Raw).Trim()
    if ($committedScript -ne $scriptBody.Trim()) {
        Write-Error @"
The committed ALZ policy catalog SCRIPT ($scriptPath) does not match the
library at the pinned ref ($libraryPath@$libraryRef).

This is the file the wizard actually loads, so a stale one means the client is
offered a policy set the deployment will not produce.

Fix: pwsh factory/ci/New-AlzPolicyCatalog.ps1
"@
        exit 1
    }
    $committed = (Get-Content $CatalogPath -Raw).Trim()
    if ($committed -ne $json.Trim()) {
        Write-Error @"
The committed ALZ policy catalog does not match the library at the pinned ref
($libraryPath@$libraryRef).

This means one of two things, and both are load-bearing:
  * the library pin in factory-version.json moved without the catalog being
    regenerated, so the wizard is offering a policy set the deployment will not
    produce; or
  * the catalog was hand-edited, which the header forbids.

Fix: pwsh factory/ci/New-AlzPolicyCatalog.ps1
"@
        exit 1
    }
    Write-Host "OK: policy catalog and script match $libraryPath@$libraryRef ($($catalog.assignments.Count) assignments, $($catalog.defaults.Count) default values)."
    exit 0
}

$json | Set-Content $CatalogPath -Encoding utf8
$scriptBody | Set-Content $scriptPath -Encoding utf8
Write-Host "Wrote $CatalogPath"
Write-Host "Wrote $scriptPath (the file the wizard loads)"
Write-Host "  library      : $libraryPath@$libraryRef"
Write-Host "  archetypes   : $($catalog.archetypes.Count)"
Write-Host "  assignments  : $($catalog.assignments.Count)"
Write-Host "  defaults     : $($catalog.defaults.Count)"
Write-Host "  groups       : $($catalog.groups.Count)"
Write-Host "  ungrouped    : $($catalog.ungrouped.Count)$(if ($catalog.ungrouped.Count) { ' -> ' + ($catalog.ungrouped -join ', ') })"
