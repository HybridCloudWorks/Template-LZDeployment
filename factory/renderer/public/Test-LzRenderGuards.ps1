#Requires -Version 7.0
<#
    Render guards — the checks that refuse to emit a repository.

    The wizard already enforces most of these client-side. They are re-enforced
    here, independently, because the renderer must be safe when driven by a
    hand-edited lz-config.json, by CI, or by a config produced by an older
    factory version. A validation that exists only in the UI is a suggestion,
    not a guarantee.

    Every guard blocks rather than warns. The failure mode being prevented is
    always the same shape: emitting Terraform that plans cleanly and then does
    nothing, or does the wrong thing.
#>

Set-StrictMode -Version Latest

function New-LzGuardViolation {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Message,
        [string]$Remediation = '',
        [ValidateSet('Block', 'Warn')][string]$Severity = 'Block'
    )
    [pscustomobject]@{ Id = $Id; Message = $Message; Remediation = $Remediation; Severity = $Severity }
}

function Get-LzGuardConfigValue {
    <#
    .SYNOPSIS
        StrictMode-safe dot-path read over a parsed configuration.
    .DESCRIPTION
        Walks Path one segment at a time via Test-LzHasProperty and returns
        Default when any segment is absent or null. The guard-chain contract:
        any configuration that passes G00 schema validation must flow through
        every guard producing structured PASS/VIOLATION/ADVISORY results —
        never a StrictMode property exception. The schema leaves whole blocks
        optional (identity, environments.approvals, security.*, ...), so every
        guard read of a path the schema does not mark required goes through
        this helper; an absent path means feature-off/default, not a crash.
    .PARAMETER Object
        Root object to read from (usually the parsed config).
    .PARAMETER Path
        Dot-separated property path, e.g. 'security.sentinel.enabled'.
    .PARAMETER Default
        Returned when any path segment is missing or null.
    #>
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Path,
        $Default = $null
    )
    $current = $Object
    foreach ($segment in $Path.Split('.')) {
        if (-not (Test-LzHasProperty $current $segment)) { return $Default }
        $current = $current.$segment
    }
    if ($null -eq $current) { return $Default }
    return $current
}

function Test-LzRenderGuards {
    <#
    .SYNOPSIS
        Validate that a configuration can actually be rendered.
    .PARAMETER Config
        Parsed lz-config.json.
    .PARAMETER FactoryVersion
        Parsed factory-version.json, used to read per-module implementation
        status so the scaffold-module guards stay in sync with reality rather
        than with a hard-coded list here.
    .OUTPUTS
        Object with Violations, BlockCount, WarnCount, CanRender.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [object]$FactoryVersion = $null
    )

    $v = @()

    # ── Contract version ─────────────────────────────────────────────────────
    if ($FactoryVersion) {
        $expected = $FactoryVersion.contracts.configSchemaVersion
        if ($Config.schemaVersion -ne $expected) {
            $v += New-LzGuardViolation -Id 'G01' `
                -Message "Configuration declares schema version '$($Config.schemaVersion)', but this factory implements '$expected'." `
                -Remediation 'Re-export the configuration from the wizard shipped with this factory version. Rendering a schema the renderer does not implement would silently drop or misplace keys.'
        }
    }

    # ── Answers recorded but not deployed by the emitted architecture ────────
    # The generator emits the AVM three-layer architecture (ADR 0013/0017).
    # Sentinel onboarding and customer-managed-key estates are per-estate work
    # done inside the generated repository. The answers are preserved in the
    # committed answer record (lz-config.json) and surfaced in the generated
    # documentation — but silence here would read as "deployed", so warn.
    if (Get-LzGuardConfigValue -Object $Config -Path 'security.sentinel.enabled' -Default $false) {
        $v += New-LzGuardViolation -Id 'G02' -Severity 'Warn' `
            -Message 'Sentinel is enabled in the configuration; the emitted architecture records the answer but does not deploy Sentinel.' `
            -Remediation 'Onboard Sentinel inside the generated repository against the management layer''s workspace. The answer is preserved in lz-config.json.'
    }

    if (Get-LzGuardConfigValue -Object $Config -Path 'security.keyVault.customerManagedKeys' -Default $false) {
        $v += New-LzGuardViolation -Id 'G03' -Severity 'Warn' `
            -Message 'Customer-managed keys are enabled in the configuration; the emitted architecture records the answer but does not deploy a CMK estate.' `
            -Remediation 'Implement the CMK estate inside the generated repository. The answer is preserved in lz-config.json.'
    }

    # ── Layers with no corpus ────────────────────────────────────────────────
    # Get-LzActiveLayers can select layers that terraform/live has never had a
    # source for. Before this guard, such a layer was emitted as a directory
    # containing only backend.tf: `terraform init` succeeded, `terraform plan`
    # reported no changes, and the operator concluded the layer had nothing to
    # do — rather than that it did not exist. Refuse instead.
    # Read from factory-version.json for the same reason the scaffold-module
    # guards do: promoting a new layer into the corpus should lift its guard by
    # declaring it there, not by editing a list here that nothing else knows
    # about. When no factory version is supplied the guard cannot decide, and
    # stays silent rather than guessing.
    $implementedLayers = @()
    if ($FactoryVersion -and (Test-LzHasProperty $FactoryVersion 'landingZone') -and
        (Test-LzHasProperty $FactoryVersion.landingZone 'layers')) {
        $implementedLayers = @($FactoryVersion.landingZone.layers)
    }
    foreach ($layer in (Get-LzActiveLayers -Config $Config)) {
        if ($implementedLayers.Count -gt 0 -and $layer -notin $implementedLayers) {
            $v += New-LzGuardViolation -Id 'G21' `
                -Message "This configuration selects the '$layer' layer, for which the template corpus has no Terraform." `
                -Remediation "Either author terraform/live/$layer and promote it into factory/templates (see `$pendingLayers in variable-map.json), or change the configuration so the layer is not selected. Emitting it would produce a layer that initialises and plans zero resources, which reads as 'nothing to do' rather than 'not implemented'."
        }
    }

    # ── Topology feature coherence ───────────────────────────────────────────
    # Both topologies are implemented (hub-and-spoke and Virtual WAN AVM
    # pattern modules; exactly one is emitted). Bastion and centralized private
    # DNS zones are composed for the hub-and-spoke topology only.
    if ($Config.connectivity.model -eq 'virtual-wan') {
        if (Get-LzGuardConfigValue -Object $Config -Path 'connectivity.bastion.enabled' -Default $false) {
            $v += New-LzGuardViolation -Id 'G04' -Severity 'Warn' `
                -Message 'Bastion is enabled with the virtual-wan topology; the emitted composition deploys Bastion only for hub-and-spoke.' `
                -Remediation 'Deploy Bastion per-spoke inside the generated repository, or use the hub-spoke topology.'
        }
        if (Get-LzGuardConfigValue -Object $Config -Path 'connectivity.privateDns.enabled' -Default $false) {
            $v += New-LzGuardViolation -Id 'G04' -Severity 'Warn' `
                -Message 'Centralized private DNS zones are enabled with the virtual-wan topology; the emitted composition creates them only for hub-and-spoke.' `
                -Remediation 'Create the zones inside the generated repository, or use the hub-spoke topology.'
        }
    }

    # Optional key: the schema requires github.{ownershipModel,ownerName,
    # repositoryName,visibility} only. Absent means GitHub-hosted (default).
    if (Get-LzGuardConfigValue -Object $Config -Path 'github.useSelfHostedRunners' -Default $false) {
        $v += New-LzGuardViolation -Id 'G05' `
            -Message 'Self-hosted runners are requested, but v1 emits GitHub-hosted workflows only.' `
            -Remediation 'Set github.useSelfHostedRunners to false. Extension point: the runs-on value is centralised in the workflow templates and can be parameterised once self-hosted runner labels are part of the schema.'
    }

    # ── Tag coverage ─────────────────────────────────────────────────────────
    # A landing zone whose own tagging policy denies its first apply is the
    # single most common self-inflicted deployment failure.
    $required = @(Get-LzGuardConfigValue -Object $Config -Path 'governance.policyBaseline.requiredTags' -Default @())
    # naming.standard is the only schema-required naming key; defaultTags may
    # be absent, which G06 must report as missing values, not crash on.
    $defaults = Get-LzGuardConfigValue -Object $Config -Path 'naming.defaultTags' -Default $null
    $missing = @()
    foreach ($t in $required) {
        $has = (Test-LzHasProperty $defaults $t) -and
               -not [string]::IsNullOrWhiteSpace([string]$defaults.$t)
        if (-not $has) { $missing += $t }
    }
    if ($missing.Count -gt 0) {
        $v += New-LzGuardViolation -Id 'G06' `
            -Message "Policy requires tag(s) [$($missing -join ', ')] but naming.defaultTags supplies no value for them." `
            -Remediation 'Add a default value for every policy-required tag. Otherwise the deployment is denied by its own tagging policy on the first apply.'
    }

    # ── Region / policy coherence ────────────────────────────────────────────
    # allowedLocations is not schema-required; when absent there is no
    # allowed-locations input to contradict, so G07/G08 have nothing to check.
    $allowed = @(Get-LzGuardConfigValue -Object $Config -Path 'azure.allowedLocations' -Default @())
    $deployedRegions = @($Config.azure.primaryRegion)
    # drRegion is optional and stripped from the export when absent; reading it
    # unconditionally throws under StrictMode on a single-region configuration.
    if (Test-LzHasProperty $Config.azure 'drRegion') { $deployedRegions += $Config.azure.drRegion }
    foreach ($r in $deployedRegions) {
        if ($allowed.Count -gt 0 -and $r -and $allowed -notcontains $r) {
            $v += New-LzGuardViolation -Id 'G07' `
                -Message "Region '$r' is deployed to but is absent from azure.allowedLocations." `
                -Remediation 'Add the region to allowedLocations. The allowed-locations policy would otherwise deny the landing zone its own resources.'
        }
    }

    $residency = @(Get-LzGuardConfigValue -Object $Config -Path 'governance.dataResidencyRegions' -Default @())
    if ($residency.Count -gt 0) {
        $outside = @($allowed | Where-Object { $_ -notin $residency })
        if ($outside.Count -gt 0) {
            $v += New-LzGuardViolation -Id 'G08' `
                -Message "Allowed locations [$($outside -join ', ')] fall outside the declared data-residency regions." `
                -Remediation 'Reconcile azure.allowedLocations with governance.dataResidencyRegions.'
        }
    }

    # ── Subscription availability per layer ──────────────────────────────────
    $subs = $Config.azure.subscriptions
    $hasSub = { param([string]$n) return ((Test-LzHasProperty $subs $n) -and $subs.$n) }

    # The management subscription hosts the management layer and anchors the
    # provider configuration of the global layer; it is always required.
    # Connectivity is required only when platform networking is deployed.
    # Workload and sandbox subscriptions are placement-only — an absent slot
    # places nothing, which is a valid estate, not a failure.
    if (-not (& $hasSub 'management')) {
        $v += New-LzGuardViolation -Id 'G09' `
            -Message "Required subscription 'management' is missing from the configuration." `
            -Remediation 'Supply the management subscription ID. The platform-management and global layers cannot be rendered without one.'
    }
    if ($Config.connectivity.model -ne 'none' -and -not (& $hasSub 'connectivity')) {
        $v += New-LzGuardViolation -Id 'G09' `
            -Message "Connectivity model '$($Config.connectivity.model)' is selected but the connectivity subscription is missing." `
            -Remediation 'Supply the connectivity subscription ID, or set connectivity.model to none.'
    }

    # The identity block is not schema-required at all; absent means no
    # dedicated identity subscription layer is requested.
    if ((Get-LzGuardConfigValue -Object $Config -Path 'identity.deployIdentitySubscription' -Default $false) -and -not (& $hasSub 'identity')) {
        $v += New-LzGuardViolation -Id 'G11' `
            -Message 'An identity subscription layer is requested but no identity subscription ID was supplied.' `
            -Remediation 'Supply azure.subscriptions.identity, or set identity.deployIdentitySubscription to false.'
    }

    # ── Address space sanity ─────────────────────────────────────────────────
    if ($Config.connectivity.model -eq 'hub-spoke') {
        $hs = Get-LzGuardConfigValue -Object $Config -Path 'connectivity.hubSpoke' -Default $null
        $spaces = @()
        foreach ($n in @('primaryHubAddressSpace', 'drHubAddressSpace', 'primarySpokeAddressSpace', 'drSpokeAddressSpace')) {
            if ((Test-LzHasProperty $hs $n) -and $hs.$n) { $spaces += , @($n, $hs.$n) }
        }
        if (Test-LzHasProperty $hs 'nonProdSpokeAddressSpaces') {
            foreach ($envName in @('dev', 'test', 'uat')) {
                if (-not (Test-LzHasProperty $hs.nonProdSpokeAddressSpaces $envName)) { continue }
                foreach ($regionName in @('primary', 'dr')) {
                    $pair = $hs.nonProdSpokeAddressSpaces.$envName
                    if ((Test-LzHasProperty $pair $regionName) -and $pair.$regionName) {
                        $spaces += , @("$envName-$regionName", $pair.$regionName)
                    }
                }
            }
        }
        for ($i = 0; $i -lt $spaces.Count; $i++) {
            for ($j = $i + 1; $j -lt $spaces.Count; $j++) {
                if (Test-LzRendererCidrOverlap -CidrA $spaces[$i][1] -CidrB $spaces[$j][1]) {
                    $v += New-LzGuardViolation -Id 'G12' `
                        -Message "Address spaces $($spaces[$i][0]) ($($spaces[$i][1])) and $($spaces[$j][0]) ($($spaces[$j][1])) overlap." `
                        -Remediation 'Overlapping ranges cannot be peered, and the failure appears only after the virtual networks exist. Choose non-overlapping CIDRs.'
                }
            }
        }
    }

    # ── Promotion path coherence ─────────────────────────────────────────────
    $app = @($Config.environments.application)
    foreach ($stage in @($Config.environments.promotionPath)) {
        if ($stage -notin $app) {
            $v += New-LzGuardViolation -Id 'G13' `
                -Message "Promotion path includes '$stage', which is not a selected application environment." `
                -Remediation 'The promotion workflow would gate on an environment that is never deployed. Re-export from the wizard, which derives the path automatically.'
        }
    }

    # ── Approval gates on production ─────────────────────────────────────────
    if ($app -contains 'prod') {
        # environments.approvals (and approvals.prod.requiredReviewers) are
        # optional; absent means no reviewers, which is exactly what G14 warns
        # about.
        $reviewers = @(Get-LzGuardConfigValue -Object $Config -Path 'environments.approvals.prod.requiredReviewers' -Default @())
        if ($reviewers.Count -eq 0) {
            $v += New-LzGuardViolation -Id 'G14' -Severity 'Warn' `
                -Message 'The prod environment has no required reviewers.' `
                -Remediation 'Production applies will run without human approval. Add reviewers unless this is deliberate.'
        }
    }

    # ── Naming patterns ──────────────────────────────────────────────────────
    if ($Config.naming.standard -eq 'custom') {
        $allowedTokens = @('org', 'scope', 'workload', 'type', 'region', 'regionCode', 'env', 'nn')
        foreach ($pair in @(
            @('resourceGroupPattern', (Get-LzGuardConfigValue -Object $Config -Path 'naming.resourceGroupPattern' -Default '')),
            @('resourcePattern', (Get-LzGuardConfigValue -Object $Config -Path 'naming.resourcePattern' -Default ''))
        )) {
            $name = $pair[0]; $pattern = $pair[1]
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                $v += New-LzGuardViolation -Id 'G15' `
                    -Message "naming.standard is 'custom' but $name is empty." `
                    -Remediation "Supply a $name, or set naming.standard to 'caf'."
                continue
            }
            foreach ($m in [regex]::Matches($pattern, '\{([^}]*)\}')) {
                $tok = $m.Groups[1].Value
                if ($tok -notin $allowedTokens) {
                    $v += New-LzGuardViolation -Id 'G16' `
                        -Message "$name uses unknown token {$tok}." `
                        -Remediation "Allowed tokens: $(($allowedTokens | ForEach-Object { '{' + $_ + '}' }) -join ' '). An unrecognised token would survive into resource names verbatim."
                }
            }
        }
    }

    # ── Backend coherence ────────────────────────────────────────────────────
    # The emitted backend is azurerm-only (ADR 0015). G17/G19 (HCP organization
    # and Sentinel-requires-HCP) retired with the dual-backend feature.
    if ($Config.backend.type -ne 'azurerm') {
        $v += New-LzGuardViolation -Id 'G17' `
            -Message "Backend type '$($Config.backend.type)' is not supported: the generator emits the azurerm backend only (ADR 0015)." `
            -Remediation 'Set backend.type to azurerm and supply the state storage coordinates.'
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-LzGuardConfigValue -Object $Config -Path 'backend.azurerm.storageAccountName' -Default ''))) {
        $v += New-LzGuardViolation -Id 'G18' `
            -Message 'No state storage account is configured.' `
            -Remediation 'Supply backend.azurerm.storageAccountName and resourceGroupName.'
    }

    # ── Repository visibility ────────────────────────────────────────────────
    if ($Config.github.visibility -eq 'internal' -and $Config.github.ownershipModel -ne 'enterprise') {
        $v += New-LzGuardViolation -Id 'G20' `
            -Message 'Internal visibility requires GitHub Enterprise Cloud.' `
            -Remediation 'Set github.visibility to private, or correct the ownership model.'
    }

    # ── Private DNS centralization ───────────────────────────────────────────
    # Contract 9 puts the private DNS zones in the connectivity layer and
    # forbids a workload layer from creating a zone of the same name — two
    # zones of one name resolve differently depending on which VNet asks, and
    # nothing surfaces the divergence. centralizedInHub = false has no
    # implementation behind it, so rendering it as if it were honoured would be
    # exactly the silent yes-means-no this guard chain exists to stop. Default
    # true: an absent key is the centralized answer (TODO item 2.12).
    # BOTH reads go through Get-LzGuardConfigValue, not just the second:
    # privateDns is not schema-required, and a direct $Config.connectivity.privateDns
    # dereference throws under StrictMode on a sparse configuration, which would
    # take the whole guard chain down instead of producing a violation.
    if ((Get-LzGuardConfigValue -Object $Config -Path 'connectivity.privateDns.enabled' -Default $false) -and
        (Get-LzGuardConfigValue -Object $Config -Path 'connectivity.privateDns.centralizedInHub' -Default $true) -eq $false) {
        $v += New-LzGuardViolation -Id 'G23' `
            -Message 'connectivity.privateDns.centralizedInHub = false is not implemented: private DNS zones are owned by the connectivity layer (cross-domain contract 9).' `
            -Remediation 'Set connectivity.privateDns.centralizedInHub to true, or disable connectivity.privateDns.enabled.'
    }

    # ── Subscription vending completeness ────────────────────────────────────
    # A create-mode configuration (azure.subscriptions.mode = create, ADR 0020)
    # is exported BEFORE the subscriptions exist: the wizard plans names, and
    # scripts/New-LzSubscriptions.ps1 creates them and patches the IDs back.
    # Rendering in between would emit placements and provider blocks pointing
    # at empty subscription IDs. G09 already blocks the required slots with a
    # generic message; G25 exists to say WHICH step was skipped.
    if ((Get-LzGuardConfigValue -Object $Config -Path 'azure.subscriptions.mode' -Default 'create') -eq 'create') {
        $plannedNames = Get-LzGuardConfigValue -Object $Config -Path 'azure.subscriptions.plannedNames' -Default $null
        if ($plannedNames) {
            $unfilled = @()
            foreach ($slot in @('management', 'connectivity', 'workloadProd', 'identity', 'workloadNonProd', 'sandbox')) {
                if (-not (Test-LzHasProperty $plannedNames $slot)) { continue }
                $id = [string](Get-LzGuardConfigValue -Object $Config -Path "azure.subscriptions.$slot" -Default '')
                if ([string]::IsNullOrWhiteSpace($id)) { $unfilled += $slot }
            }
            if ($unfilled.Count -gt 0) {
                $v += New-LzGuardViolation -Id 'G25' `
                    -Message "Subscription slot(s) [$($unfilled -join ', ')] are planned by name but carry no subscription ID yet (azure.subscriptions.mode = create)." `
                    -Remediation 'Run scripts/New-LzSubscriptions.ps1 -ConfigPath <lz-config.json> -Apply to create the planned subscriptions and write the IDs back, then render again. Rendering now would emit layers bound to empty subscription IDs.'
            }
        }
    }

    # ── Brownfield exclusion integrity ───────────────────────────────────────
    # Exclude-and-create (ADR 0018): an excluded subscription is one this
    # landing zone must never place, permission, or policy. The same ID
    # appearing in a subscription slot would do all three.
    $excludedIds = @(Get-LzGuardConfigValue -Object $Config -Path 'deploymentStrategy.brownfield.excludedSubscriptionIds' -Default @())
    if ($excludedIds.Count -gt 0) {
        foreach ($slot in @('management', 'connectivity', 'workloadProd', 'identity', 'workloadNonProd', 'sandbox')) {
            $id = [string](Get-LzGuardConfigValue -Object $Config -Path "azure.subscriptions.$slot" -Default '')
            if ($id -and $excludedIds -contains $id) {
                $v += New-LzGuardViolation -Id 'G26' `
                    -Message "Subscription $id is on the brownfield exclusion list but is assigned to the '$slot' slot." `
                    -Remediation 'A subscription cannot be both excluded from the landing zone and part of its new estate (ADR 0018). Remove it from deploymentStrategy.brownfield.excludedSubscriptionIds or assign a different subscription to the slot.'
            }
        }
    }

    # ── State private-endpoint prerequisites ─────────────────────────────────
    # Day-0 state posture is public endpoint + Entra-only auth (ADR 0019); the
    # hardening overlay moves state behind a private endpoint and is only
    # coherent when the hub, centralized private DNS, and runners that live
    # inside the network all exist. Emitting it without them produces a state
    # account the pipeline itself cannot reach — self-lockout as a rendered
    # artifact.
    if (Get-LzGuardConfigValue -Object $Config -Path 'backend.azurerm.privateEndpoint.enabled' -Default $false) {
        $peMissing = @()
        if ($Config.connectivity.model -ne 'hub-spoke') { $peMissing += 'the hub-and-spoke topology' }
        if (-not ((Get-LzGuardConfigValue -Object $Config -Path 'connectivity.privateDns.enabled' -Default $false) -and
                (Get-LzGuardConfigValue -Object $Config -Path 'connectivity.privateDns.centralizedInHub' -Default $true))) {
            $peMissing += 'centralized private DNS in the hub'
        }
        if (-not (Get-LzGuardConfigValue -Object $Config -Path 'github.useSelfHostedRunners' -Default $false)) {
            $peMissing += 'self-hosted runners with a network path to the hub'
        }
        if ($peMissing.Count -gt 0) {
            $v += New-LzGuardViolation -Id 'G27' `
                -Message "backend.azurerm.privateEndpoint.enabled requires $($peMissing -join ', ')." `
                -Remediation 'Set backend.azurerm.privateEndpoint.enabled to false (the day-0 posture: public endpoint, Entra-only auth, versioning, soft delete, delete lock — ADR 0019), or satisfy every prerequisite. A private-only state account that the deployment runners cannot reach locks the pipeline out of its own state.'
        }
    }

    $blocks = @($v | Where-Object { $_.Severity -eq 'Block' })
    $warns = @($v | Where-Object { $_.Severity -eq 'Warn' })

    [pscustomobject]@{
        Violations = $v
        BlockCount = $blocks.Count
        WarnCount  = $warns.Count
        CanRender  = ($blocks.Count -eq 0)
    }
}

function Test-LzRendererCidrOverlap {
    <#
    .SYNOPSIS
        True when two IPv4 CIDR ranges intersect.
    .DESCRIPTION
        Duplicated from the discovery engine rather than shared, so the renderer
        has no dependency on the discovery module — the two run at different
        phases and must be independently usable. Arithmetic is int64 because
        PowerShell's -bnot on uint32 yields a signed value.
    #>
    param(
        [Parameter(Mandatory)][string]$CidrA,
        [Parameter(Mandatory)][string]$CidrB
    )

    function ConvertTo-Range([string]$cidr) {
        if ($cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') { return $null }
        $ip = $Matches[1]; $bits = [int]$Matches[2]
        if ($bits -lt 0 -or $bits -gt 32) { return $null }
        $octets = @($ip -split '\.' | ForEach-Object { [int]$_ })
        if (@($octets | Where-Object { $_ -gt 255 }).Count -gt 0) { return $null }

        [int64]$addr = ([int64]$octets[0] -shl 24) -bor ([int64]$octets[1] -shl 16) -bor
                       ([int64]$octets[2] -shl 8)  -bor  [int64]$octets[3]
        [int64]$mask = if ($bits -eq 0) { 0L } else { (0xFFFFFFFFL -shl (32 - $bits)) -band 0xFFFFFFFFL }
        [int64]$net = $addr -band $mask
        return @($net, ($net -bor (0xFFFFFFFFL -bxor $mask)))
    }

    $a = ConvertTo-Range $CidrA
    $b = ConvertTo-Range $CidrB
    if (-not $a -or -not $b) { return $false }
    return ($a[0] -le $b[1] -and $b[0] -le $a[1])
}
