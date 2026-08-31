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
    # Two backends again (decision 0023, partially reversing 0015). G17 was a
    # const-refusal of everything but azurerm while there was only one backend;
    # it now carries the coherence checks that belong to each.
    $backendType = [string](Get-LzGuardConfigValue -Object $Config -Path 'backend.type' -Default 'azurerm')
    if ($backendType -eq 'hcp-terraform') {
        # backend.hcpTerraform may exist without .organization; the nested read
        # must not crash where G17 is supposed to report the gap.
        if ([string]::IsNullOrWhiteSpace([string](Get-LzGuardConfigValue -Object $Config -Path 'backend.hcpTerraform.organization' -Default ''))) {
            $v += New-LzGuardViolation -Id 'G17' `
                -Message 'Backend is hcp-terraform but no organization is configured.' `
                -Remediation 'Supply backend.hcpTerraform.organization. Workspaces are created as {prefix}-{layer} inside it.'
        }
        $executionMode = [string](Get-LzGuardConfigValue -Object $Config -Path 'backend.hcpTerraform.executionMode' -Default 'local')
        if ($executionMode -and $executionMode -ne 'local') {
            $v += New-LzGuardViolation -Id 'G17' `
                -Message "HCP Terraform execution mode '$executionMode' is not supported: this factory uses HCP Terraform for state only." `
                -Remediation 'Set backend.hcpTerraform.executionMode to local, or omit it. The emitted plan and apply workflows gate destroys on a saved plan file, and TFC remote runs do not support terraform plan -out — remote execution would delete that gate without saying so.'
        }
        # The state-hardening layer puts a private endpoint in front of a state
        # storage account this backend does not create.
        $peEnabled = [bool](Get-LzGuardConfigValue -Object $Config -Path 'backend.azurerm.privateEndpoint.enabled' -Default $false)
        if ($peEnabled) {
            $v += New-LzGuardViolation -Id 'G17' `
                -Message 'backend.azurerm.privateEndpoint.enabled is set while the backend is hcp-terraform.' `
                -Remediation 'Clear the flag, or switch the backend to azurerm. The state-hardening layer reads the state storage account as a data source and puts a private endpoint in front of it; under HCP Terraform there is no such account, so the layer would point at nothing.'
        }
    }
    elseif ($backendType -eq 'azurerm') {
        if ([string]::IsNullOrWhiteSpace([string](Get-LzGuardConfigValue -Object $Config -Path 'backend.azurerm.storageAccountName' -Default ''))) {
            $v += New-LzGuardViolation -Id 'G18' `
                -Message 'No state storage account is configured.' `
                -Remediation 'Supply backend.azurerm.storageAccountName and resourceGroupName.'
        }
    }
    else {
        $v += New-LzGuardViolation -Id 'G17' `
            -Message "Backend type '$backendType' is not supported: this factory emits azurerm or hcp-terraform." `
            -Remediation 'Set backend.type to azurerm or hcp-terraform.'
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

    # ── Brownfield dispositions ──────────────────────────────────────────────
    # ADR 0018 made brownfield recognise-and-exclude. The amendment lets a
    # client say otherwise per subscription, and G30 is what makes that a
    # decision rather than a default: placing an existing subscription into the
    # new hierarchy starts every ALZ assignment above it evaluating resources
    # that were built under different rules, on the first apply, with no
    # separate confirmation step anywhere else in the motion.
    #
    # The acknowledgement is a sentence naming the subscription rather than a
    # boolean, on the same reasoning as the state-access-flip workflow's typed
    # confirmation: the expected string is composed here from the configuration,
    # so it cannot be satisfied by copying a value from a template.
    $dispositions = Get-LzGuardConfigValue -Object $Config -Path 'deploymentStrategy.brownfield.dispositions' -Default $null
    $excludedForDisposition = @(Get-LzGuardConfigValue -Object $Config -Path 'deploymentStrategy.brownfield.excludedSubscriptionIds' -Default @())
    foreach ($subscriptionId in @(Get-LzPropertyNames $dispositions)) {
        $entry = $dispositions.$subscriptionId
        $action = [string](Get-LzGuardConfigValue -Object $entry -Path 'action' -Default '')

        if ($action -eq 'place-now') {
            $expected = Get-LzPlacementAcknowledgement -SubscriptionId $subscriptionId
            $supplied = ([string](Get-LzGuardConfigValue -Object $entry -Path 'acknowledgement' -Default '')).Trim()
            if ($supplied -ne $expected) {
                $v += New-LzGuardViolation -Id 'G30' `
                    -Message "Subscription $subscriptionId is set to place-now without a matching acknowledgement." `
                    -Remediation "Placing an existing subscription applies the landing zone policy set to the resources already in it, on the first apply. Set deploymentStrategy.brownfield.dispositions.'$subscriptionId'.acknowledgement to exactly: $expected — or set action to defer, which leaves the subscription outside the hierarchy and generates written onboarding instructions for it."
            }
            # place-now and excluded are opposite instructions about the same
            # subscription. G26 catches the slot case; this catches the pair.
            if ($excludedForDisposition -contains $subscriptionId) {
                $v += New-LzGuardViolation -Id 'G30' `
                    -Message "Subscription $subscriptionId is on the brownfield exclusion list and also set to place-now." `
                    -Remediation 'A subscription cannot be both kept out of the landing zone and placed into it. Remove it from excludedSubscriptionIds, or change the disposition to defer.'
            }
        }
        elseif ($action -ne 'defer') {
            $v += New-LzGuardViolation -Id 'G30' `
                -Message "Subscription $subscriptionId carries an unrecognised disposition '$action'." `
                -Remediation 'Use place-now or defer.'
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

    # ── G28: a selected policy assignment whose default value nobody supplied ──
    # The ALZ provider resolves policy_default_values at PLAN time, which nothing
    # in this pipeline runs, so an unsupplied value is invisible to every other
    # gate: the assignment is created from the placeholder in the library's own
    # assignment file — security_contact@replace_me, or a plan under an
    # all-zeroes subscription — and only misbehaves at remediation time. The
    # wizard blocks the same case at export; this guard is what stops a
    # hand-edited configuration from walking past it.
    $policy = Resolve-LzPolicySelection -Config $Config
    $catalog = Get-LzPolicyCatalog
    $answers = $null
    if ((Test-LzHasProperty $Config.governance 'policySelection') -and
        (Test-LzHasProperty $Config.governance.policySelection 'values')) {
        $answers = $Config.governance.policySelection.values
    }
    foreach ($name in @(Get-LzPropertyNames $catalog.defaults)) {
        $declaration = $catalog.defaults.$name
        if ($declaration.supplied -eq 'factory') { continue }
        $asking = @(@($declaration.consumedBy | ForEach-Object { $_.assignment }) |
            Where-Object { $_ -in $policy.CreatedAssignments } | Sort-Object -Unique)
        if ($asking.Count -eq 0) { continue }
        $supplied = ''
        if ($answers -and (Test-LzHasProperty $answers $name)) { $supplied = [string]$answers.$name }
        if ($supplied.Trim()) { continue }
        $v += New-LzGuardViolation -Id 'G28' `
            -Message "governance.policySelection.values.$name is required: $($asking -join ', ') is selected and the pinned ALZ library declares no usable default." `
            -Remediation "Supply the value, or turn the assignment off in the wizard's Policies step. Created without it, the assignment carries the library's own placeholder, which either fails ARM validation or is accepted and then remediates against something that does not exist."
    }

    # ── G29: a management-group rename the pinned library cannot honour ───────
    # Renames are keyed by the library's own management-group id. A key the
    # library does not define emits a group into the architecture definition
    # that no archetype claims: created, governed by nothing, and — because
    # management-group IDs are immutable in Azure — not correctable by a later
    # apply. Two groups resolving to the same id is the same failure with a
    # collision on top. The wizard blocks both at export; this is what stops a
    # hand-edited answer record.
    if ($Config.azure.managementGroups.strategy -eq 'custom') {
        $mgCatalog = Get-LzPolicyCatalog
        $libraryIds = @($mgCatalog.managementGroups | ForEach-Object { $_.id })
        $renames = if (Test-LzHasProperty $Config.azure.managementGroups 'customHierarchy') {
            $Config.azure.managementGroups.customHierarchy
        }
        else { $null }

        foreach ($name in @(Get-LzPropertyNames $renames)) {
            if ($name -notin $libraryIds) {
                $v += New-LzGuardViolation -Id 'G29' `
                    -Message "azure.managementGroups.customHierarchy renames '$name', which the ALZ library at $($mgCatalog.library.ref) does not define." `
                    -Remediation "Rename one of: $($libraryIds -join ', '). A key outside that set would create a management group no archetype governs, and management-group IDs are immutable once applied."
            }
        }

        $resolved = Resolve-LzManagementGroups -Config $Config
        $seen = @{}
        foreach ($libraryId in $libraryIds) {
            $id = $resolved.Effective[$libraryId].id
            if ($seen.ContainsKey($id)) {
                $v += New-LzGuardViolation -Id 'G29' `
                    -Message "Management groups '$($seen[$id])' and '$libraryId' both resolve to the id '$id'." `
                    -Remediation 'Give each management group a distinct id. Two groups cannot share one, and the apply would fail after creating the first.'
            }
            $seen[$id] = $libraryId
        }

        # "Renames nothing" has to mean the effective names are the library's,
        # not that the map is empty. { "alz": {} } and { "alz": { "id": "alz" } }
        # are both non-empty and both change nothing — and both would still emit
        # a local architecture definition, pinning the estate to a copy of the
        # library that a bump can no longer update. The wizard strips no-op
        # renames on export; this is what catches a hand-edited record.
        $changed = 0
        foreach ($group in @($mgCatalog.managementGroups)) {
            $current = $resolved.Effective[$group.id]
            if ($current.id -ne $group.id -or $current.displayName -ne $group.displayName) { $changed++ }
        }
        if ($changed -eq 0) {
            $v += New-LzGuardViolation -Id 'G29' `
                -Message 'The custom hierarchy strategy is selected but every management group still resolves to its library name.' `
                -Remediation "Rename at least one group so its id or display name differs from the pinned library's, or set azure.managementGroups.strategy to caf-standard. Emitting a custom architecture identical to the library's would pin this estate to a local copy that a library bump can no longer update."
        }
    }

    # G31 — caf-minimal creates no Sandbox management group, so a sandbox
    # subscription has nowhere to be placed.
    #
    # This has to be an error rather than a silent drop or a quiet re-placement.
    # The global layer's active_placements filters slots whose subscription id
    # is EMPTY, not slots whose management group is missing, so a populated
    # sandbox slot under caf-minimal reaches the apply and fails there — after
    # the rest of the hierarchy has been created, with management-group ids that
    # are immutable. Placing it somewhere else instead would put a sandbox
    # subscription under a governed archetype without anyone choosing that.
    if ($Config.azure.managementGroups.strategy -eq 'caf-minimal') {
        $sandboxSubscription = [string](Get-LzGuardConfigValue -Object $Config -Path 'azure.subscriptions.sandbox' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($sandboxSubscription)) {
            $v += New-LzGuardViolation -Id 'G31' `
                -Message 'azure.subscriptions.sandbox is set while azure.managementGroups.strategy is caf-minimal, which creates no Sandbox management group.' `
                -Remediation 'Either set azure.managementGroups.strategy to caf-standard, which creates Sandbox and Decommissioned, or clear azure.subscriptions.sandbox. The subscription would otherwise be placed under a management group this estate never creates, and the failure would land mid-apply.'
        }
    }

    # G32 / G33 — the default subscription budget.
    #
    # Deploy-Budget reaches subscriptions through a management group, so the
    # group has to be one this estate actually creates. caf-minimal creates ten
    # of the library's twelve, and the schema's enum lists all twelve — it
    # cannot know the strategy. Left unguarded, the render emits an architecture
    # definition binding an override archetype to a group that is not in it, and
    # the provider fails at plan time with a message about an unknown archetype
    # rather than about a budget.
    $budgetEnabled = [bool](Get-LzGuardConfigValue -Object $Config -Path 'finops.defaultSubscriptionBudget.enabled' -Default $false)
    if ($budgetEnabled) {
        $budgetGroup = [string](Get-LzGuardConfigValue -Object $Config -Path 'finops.defaultSubscriptionBudget.managementGroup' -Default 'alz')
        $emitted = @((Resolve-LzManagementGroups -Config $Config).EmittedGroupIds)
        if ($budgetGroup -notin $emitted) {
            $v += New-LzGuardViolation -Id 'G32' `
                -Message ("finops.defaultSubscriptionBudget.managementGroup is '{0}', which the '{1}' hierarchy strategy does not create." -f $budgetGroup, $Config.azure.managementGroups.strategy) `
                -Remediation ("Choose one of the management groups this estate creates ({0}), or change azure.managementGroups.strategy to one that creates '{1}'." -f (($emitted | Sort-Object) -join ', '), $budgetGroup)
        }

        # Two thresholds that are equal produce two identical notifications at
        # the same moment, and a warning above the cap fires after it. Neither
        # is rejected by Azure, which is why it has to be rejected here: the
        # client would get a budget that works and tells them nothing useful.
        $warning = [int](Get-LzGuardConfigValue -Object $Config -Path 'finops.defaultSubscriptionBudget.warningThresholdPercent' -Default 90)
        $cap = [int](Get-LzGuardConfigValue -Object $Config -Path 'finops.defaultSubscriptionBudget.capThresholdPercent' -Default 100)
        if ($warning -ge $cap) {
            $v += New-LzGuardViolation -Id 'G33' `
                -Message ("finops.defaultSubscriptionBudget.warningThresholdPercent ({0}) is not below capThresholdPercent ({1})." -f $warning, $cap) `
                -Remediation 'Set the warning threshold below the cap. Deploy-Budget notifies at both and stops spend at neither, so an equal pair sends two identical alerts and an inverted pair warns after the cap has already been passed.'
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

function Get-LzPlacementAcknowledgement {
    <#
    .SYNOPSIS
        The exact sentence a client must type to place an existing subscription.
    .DESCRIPTION
        Composed in one place because three consumers compare against it — the
        render guard, the wizard's own export block, and the generated
        documentation. Two of them agreeing and one not would produce a
        configuration that exports and then refuses to render.

        It names the subscription deliberately: a sentence that is the same for
        every estate is one a client can paste without reading, and reading it
        is the entire control.
    #>
    param([Parameter(Mandatory)][string]$SubscriptionId)
    return "I accept that $SubscriptionId will be governed by the landing zone policy set, including its existing resources."
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
