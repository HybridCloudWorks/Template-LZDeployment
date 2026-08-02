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

    # ── Scaffold modules ─────────────────────────────────────────────────────
    # Read status from factory-version.json rather than hard-coding, so
    # implementing a module automatically lifts its guard.
    $moduleStatus = @{}
    if ($FactoryVersion -and (Test-LzHasProperty $FactoryVersion 'modules')) {
        foreach ($p in $FactoryVersion.modules.PSObject.Properties) {
            if ($p.Value -is [psobject] -and (Test-LzHasProperty $p.Value 'status')) {
                $moduleStatus[$p.Name] = $p.Value.status
            }
        }
    }

    $isScaffold = {
        param([string]$name)
        return ($moduleStatus.ContainsKey($name) -and $moduleStatus[$name] -eq 'scaffold')
    }

    # security is schema-required but its sub-blocks are not: an absent
    # security.sentinel / security.keyVault means the feature is off.
    if ((Get-LzGuardConfigValue -Object $Config -Path 'security.sentinel.enabled' -Default $false) -and (& $isScaffold 'sentinel-siem')) {
        $v += New-LzGuardViolation -Id 'G02' `
            -Message 'Sentinel is enabled, but the sentinel-siem module is scaffold-only and declares no resources.' `
            -Remediation 'Implement terraform/modules/sentinel-siem and set its status to "implemented" in factory-version.json, or disable Sentinel. Emitting it now would produce a layer that applies successfully and deploys nothing.'
    }

    if ((Get-LzGuardConfigValue -Object $Config -Path 'security.keyVault.customerManagedKeys' -Default $false) -and (& $isScaffold 'keyvault-cmk')) {
        $v += New-LzGuardViolation -Id 'G03' `
            -Message 'Customer-managed keys are enabled, but the keyvault-cmk module is scaffold-only and declares no resources.' `
            -Remediation 'Implement terraform/modules/keyvault-cmk and update its status in factory-version.json, or disable customer-managed keys. A no-op CMK module means data you believe is protected by your own keys is not.'
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

    # ── Unimplemented topologies ─────────────────────────────────────────────
    if ($Config.connectivity.model -eq 'virtual-wan') {
        $v += New-LzGuardViolation -Id 'G04' `
            -Message 'Connectivity model is virtual-wan, but no virtual-wan module exists in the corpus.' `
            -Remediation 'Use hub-spoke, or contribute a virtual-wan module and register it in factory-version.json.'
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

    foreach ($req in @('management', 'connectivity', 'workloadProd')) {
        if (-not (& $hasSub $req)) {
            $v += New-LzGuardViolation -Id 'G09' `
                -Message "Required subscription '$req' is missing from the configuration." `
                -Remediation "Supply the $req subscription ID. The layer consuming it cannot be rendered without one."
        }
    }

    if ($Config.environments.application -contains 'sandbox' -and -not (& $hasSub 'sandbox')) {
        $v += New-LzGuardViolation -Id 'G10' -Severity 'Warn' `
            -Message 'A sandbox environment is selected but no sandbox subscription was supplied.' `
            -Remediation 'The sandbox layer will be omitted from the output. Supply a sandbox subscription ID to emit it.'
    }

    $nonProdEnvironments = @($Config.environments.application | Where-Object { $_ -in @('dev', 'test', 'uat') })
    if ($nonProdEnvironments.Count -gt 0 -and -not (& $hasSub 'workloadNonProd')) {
        $v += New-LzGuardViolation -Id 'G22' `
            -Message 'A non-production environment is selected but azure.subscriptions.workloadNonProd is missing.' `
            -Remediation 'Supply the shared non-production workload subscription ID.'
    }
    if ($nonProdEnvironments.Count -gt 0) {
        # connectivity.hubSpoke is itself optional (only .model is required),
        # so the read must be safe from the hubSpoke segment down.
        $pairs = Get-LzGuardConfigValue -Object $Config -Path 'connectivity.hubSpoke.nonProdSpokeAddressSpaces' -Default $null
        foreach ($envName in $nonProdEnvironments) {
            if ($null -eq $pairs -or -not (Test-LzHasProperty $pairs $envName) -or
                -not (Test-LzHasProperty $pairs.$envName 'primary') -or -not $pairs.$envName.primary) {
                $v += New-LzGuardViolation -Id 'G22' `
                    -Message "Environment '$envName' is selected but has no primary non-production spoke CIDR." `
                    -Remediation "Supply connectivity.hubSpoke.nonProdSpokeAddressSpaces.$envName.primary."
                continue
            }
            if ((Test-LzHasProperty $Config.azure 'drRegion') -and $Config.azure.drRegion -and
                (-not (Test-LzHasProperty $pairs.$envName 'dr') -or -not $pairs.$envName.dr)) {
                $v += New-LzGuardViolation -Id 'G22' `
                    -Message "Environment '$envName' is selected in a dual-region configuration but has no DR spoke CIDR." `
                    -Remediation "Supply connectivity.hubSpoke.nonProdSpokeAddressSpaces.$envName.dr."
            }
        }
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
    if ($Config.backend.type -eq 'hcp-terraform') {
        # backend.hcpTerraform may exist without .organization; the nested
        # read must not crash where G17 is supposed to report the gap.
        if ([string]::IsNullOrWhiteSpace([string](Get-LzGuardConfigValue -Object $Config -Path 'backend.hcpTerraform.organization' -Default ''))) {
            $v += New-LzGuardViolation -Id 'G17' `
                -Message 'Backend is hcp-terraform but no organization is configured.' `
                -Remediation 'Supply backend.hcpTerraform.organization.'
        }
    }
    elseif ($Config.backend.type -eq 'azurerm') {
        if ([string]::IsNullOrWhiteSpace([string](Get-LzGuardConfigValue -Object $Config -Path 'backend.azurerm.storageAccountName' -Default ''))) {
            $v += New-LzGuardViolation -Id 'G18' `
                -Message 'Backend is azurerm but no state storage account is configured.' `
                -Remediation 'Supply backend.azurerm.storageAccountName and resourceGroupName.'
        }
    }

    if (@(Get-LzGuardConfigValue -Object $Config -Path 'governance.policyAsCodeEngines' -Default @()) -contains 'sentinel' -and $Config.backend.type -ne 'hcp-terraform') {
        $v += New-LzGuardViolation -Id 'G19' `
            -Message 'Sentinel policy enforcement requires the HCP Terraform backend.' `
            -Remediation 'Remove sentinel from governance.policyAsCodeEngines, or switch the backend to hcp-terraform.'
    }

    # ── Repository visibility ────────────────────────────────────────────────
    if ($Config.github.visibility -eq 'internal' -and $Config.github.ownershipModel -ne 'enterprise') {
        $v += New-LzGuardViolation -Id 'G20' `
            -Message 'Internal visibility requires GitHub Enterprise Cloud.' `
            -Remediation 'Set github.visibility to private, or correct the ownership model.'
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
