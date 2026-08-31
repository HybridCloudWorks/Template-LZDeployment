#Requires -Version 7.0
<#
    Landing Zone Factory — token engine.

    TOKEN SYNTAX AND WHY IT LOOKS LIKE THIS
    ---------------------------------------
    Templates are tokenised with {{FACTORY:...}}, never with ${...}. Terraform
    uses ${...} for its own interpolation, so a factory token sharing that
    syntax would be ambiguous inside every .tf file in the corpus and would
    break `terraform fmt` on the raw template. This is control AR4 in
    the Factory-Design wiki page (https://github.com/HybridCloudWorks/Template-LZDeployment/wiki/Factory-Design).

    Conditional directives are comment-prefixed (#{{IF ...}}) so that an
    unrendered template is still syntactically valid HCL, YAML, or Markdown.
    That is what allows `terraform validate` to run against the template corpus
    itself in factory CI, catching a broken template before any customer
    renders it.

    FAIL-CLOSED
    -----------
    Every unknown token, unbalanced directive, and unresolved placeholder is a
    hard error. A renderer that silently emits an empty string for a token it
    does not recognise produces Terraform that plans successfully and deploys
    the wrong thing — which is strictly worse than not rendering at all.
#>

Set-StrictMode -Version Latest

# ══════════════════════════════════════════════════════════════════════════════
#  Token patterns
# ══════════════════════════════════════════════════════════════════════════════

# {{FACTORY:path}}          -> quoted HCL string / plain text
# {{FACTORY-RAW:path}}      -> unquoted, verbatim
# {{FACTORY-BOOL:path}}     -> true | false, unquoted
# {{FACTORY-NUM:path}}      -> numeric literal, unquoted
# {{FACTORY-LIST:path}}     -> ["a", "b"]
# {{FACTORY-MAP:path}}      -> { k = "v" } (HCL map body)
# {{FACTORY-JSON:path}}     -> compact JSON
$script:LzTokenPattern = '\{\{FACTORY(?<kind>|-RAW|-BOOL|-NUM|-LIST|-MAP|-JSON):(?<path>[A-Za-z0-9_.\[\]-]+)\}\}'

# Any surviving {{...}} after rendering indicates a typo such as
# {{FACTORY-LST:...}} that the main pattern did not match.
#
# The negative lookbehind is essential, not defensive: GitHub Actions uses
# ${{ ... }} for its own runtime expressions, and every generated workflow is
# full of them. Those must survive rendering untouched — they are evaluated by
# the Actions runner, not by the factory. Flagging them would make it impossible
# to template a workflow at all.
#
# Consequence worth knowing: a factory token mistyped as ${{FACTORY:x}} is
# invisible to this check. That is the correct trade — GitHub expressions are
# common and legitimate, while a leading $ on a factory token is not a mistake
# anyone makes by accident.
$script:LzResidualPattern = '(?<!\$)\{\{[^}]*\}\}'

$script:LzDirectivePattern = '^\s*(?:#|//|<!--)\s*\{\{(?<directive>IF|ELSEIF|ELSE|ENDIF|FOREACH|ENDFOREACH)(?:\s+(?<expr>.*?))?\}\}\s*(?:-->)?\s*$'

# ══════════════════════════════════════════════════════════════════════════════
#  Render context
# ══════════════════════════════════════════════════════════════════════════════

function New-LzRenderContext {
    <#
    .SYNOPSIS
        Build the token lookup table from a validated configuration.
    .DESCRIPTION
        Produces a flat map of dotted paths to values, plus a `computed.*`
        namespace holding values derived from the configuration rather than
        stored in it (org prefix, repository slug, OIDC subjects, layer lists).

        Deriving these once, here, is deliberate: if each template computed its
        own OIDC subject string, a single inconsistent template would produce a
        federated credential that never matches and a CI job that fails only at
        the first apply.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [object]$Discovery = $null,
        [object]$FactoryVersion = $null,
        [string]$SchemaPath = $null
    )

    $map = [ordered]@{}

    # Flatten the configuration itself.
    Add-LzFlattenedObject -Target $map -Object $Config -Prefix ''

    # Then fill in schema defaults for optional keys the document omits, so a
    # schema-valid configuration cannot fail the render with "Unknown
    # configuration path". Config values always win: seeding never overwrites.
    if ($SchemaPath -and (Test-Path $SchemaPath)) {
        $schemaDocument = Get-Content $SchemaPath -Raw | ConvertFrom-Json -Depth 30
        Add-LzSchemaDefault -Target $map -Node $schemaDocument -Prefix '' -Root $schemaDocument
    }

    # ── Computed values ──────────────────────────────────────────────────────
    $short = $Config.organization.companyShortName
    $owner = $Config.github.ownerName
    $repo = $Config.github.repositoryName
    $slug = "$owner/$repo"

    $map['computed.orgPrefix'] = $short
    $map['computed.repositorySlug'] = $slug
    $map['computed.repositoryUrl'] = "https://github.com/$slug"
    $map['computed.defaultBranch'] = $Config.github.defaultBranch
    $map['computed.generatedAt'] = $Config.generatedAt

    # Date-only form of generatedAt. Terraform variables that carry an ISO date
    # (the sandbox lifecycle tags, for one) validate against ^\d{4}-\d{2}-\d{2}$
    # and reject a full timestamp, so the truncation happens once here rather
    # than in each template that needs it.
    $map['computed.generatedDate'] = ([string]$Config.generatedAt) -replace 'T.*$', ''
    $map['computed.factoryVersion'] = $Config.factoryVersion
    $map['computed.schemaVersion'] = $Config.schemaVersion
    if ($FactoryVersion) {
        $map['computed.terraformVersion'] = $FactoryVersion.toolchain.terraform.tested
    }

    # drRegion is optional, and an exported configuration STRIPS optional keys
    # rather than emitting them empty. Under StrictMode a bare property read
    # therefore throws on every single-region landing zone, which is why the
    # existence check comes first rather than relying on $null being falsy.
    $hasDr = (Test-LzHasProperty $Config.azure 'drRegion') -and $Config.azure.drRegion
    $map['computed.hasDrRegion'] = [bool]$hasDr
    $map['computed.regionCount'] = if ($hasDr) { 2 } else { 1 }

    $platform = @($Config.environments.platform)
    $application = @($Config.environments.application)
    $map['computed.allEnvironments'] = @($platform + $application)
    $map['computed.environmentCount'] = ($platform.Count + $application.Count)

    # Layers are emitted per environment; the list drives both the workflow
    # matrix and the workspace naming, so it must be computed once.
    $map['computed.layers'] = Get-LzActiveLayers -Config $Config
    $map['computed.layersCsv'] = (@($map['computed.layers']) -join ',')

    # Which state backend is emitted (decision 0023, partially reversing 0015).
    # Both flags and the workspace prefix are set unconditionally, empty rather
    # than absent on the path that does not use them: an unknown template path
    # THROWS at render time, so a token that exists only under one backend turns
    # every #{{IF}} referencing it into a render failure on the other.
    $backendType = if (Test-LzHasProperty $Config.backend 'type') { [string]$Config.backend.type } else { 'azurerm' }
    $map['computed.backendIsAzurerm'] = ($backendType -eq 'azurerm')
    $map['computed.backendIsHcp'] = ($backendType -eq 'hcp-terraform')

    $workspacePrefix = ''
    $hcpOrganization = ''
    if ($backendType -eq 'hcp-terraform' -and (Test-LzHasProperty $Config.backend 'hcpTerraform')) {
        $hcp = $Config.backend.hcpTerraform
        $hcpOrganization = [string]$hcp.organization
        if ((Test-LzHasProperty $hcp 'workspacePrefix') -and ([string]$hcp.workspacePrefix).Trim()) {
            $workspacePrefix = ([string]$hcp.workspacePrefix).Trim()
        }
        else { $workspacePrefix = [string]$short }
    }
    $map['computed.workspacePrefix'] = $workspacePrefix
    $map['computed.hcpOrganization'] = $hcpOrganization

    # Brownfield dispositions, split for the templates that render them. Both
    # lists are objects rather than bare ids so a FOREACH body can reach the
    # note the client left, and both are always present — empty rather than
    # absent, because an unknown token path throws at render time.
    $deferred = [System.Collections.Generic.List[object]]::new()
    $placed = [System.Collections.Generic.List[object]]::new()
    $dispositions = $null
    if ((Test-LzHasProperty $Config 'deploymentStrategy') -and
        (Test-LzHasProperty $Config.deploymentStrategy 'brownfield') -and
        (Test-LzHasProperty $Config.deploymentStrategy.brownfield 'dispositions')) {
        $dispositions = $Config.deploymentStrategy.brownfield.dispositions
    }
    foreach ($subscriptionId in @(Get-LzPropertyNames $dispositions | Sort-Object)) {
        $entry = $dispositions.$subscriptionId
        $note = if (Test-LzHasProperty $entry 'note') { [string]$entry.note } else { '' }
        $record = [pscustomobject]@{ id = $subscriptionId; note = $note }
        if ([string]$entry.action -eq 'defer') { $deferred.Add($record) } else { $placed.Add($record) }
    }
    $map['computed.deferredSubscriptions'] = @($deferred)
    $map['computed.placedSubscriptions'] = @($placed)
    $map['computed.hasDeferredSubscriptions'] = ($deferred.Count -gt 0)
    # Used by the onboarding document's sample command. A real id from this
    # estate rather than a <placeholder>: the document is read by someone about
    # to run the command, and a placeholder is one more thing to get wrong.
    $map['computed.placementExampleSubscription'] = if ($deferred.Count -gt 0) { $deferred[0].id } else { '<subscription-id>' }
    $map['computed.hasPlacedSubscriptions'] = ($placed.Count -gt 0)

    # The subscription hosting the state storage account: the explicit
    # backend.azurerm.subscriptionId when supplied, else the management
    # subscription — the same fallback the broker and backend.hcl use.
    # Computed once so the state-hardening layer and the flip workflow can
    # never disagree about where state lives.
    $stateSub = ''
    if ((Test-LzHasProperty $Config.backend 'azurerm') -and
        (Test-LzHasProperty $Config.backend.azurerm 'subscriptionId')) {
        $stateSub = [string]$Config.backend.azurerm.subscriptionId
    }
    if (-not $stateSub) { $stateSub = [string]$Config.azure.subscriptions.management }
    $map['computed.stateSubscriptionId'] = $stateSub

    # Network topology drives which connectivity pattern module is emitted —
    # hub-and-spoke or Virtual WAN, never both. Computed once so no template
    # can disagree about the topology.
    $map['computed.topologyIsHubSpoke'] = ($Config.connectivity.model -eq 'hub-spoke')
    $map['computed.topologyIsVwan'] = ($Config.connectivity.model -eq 'virtual-wan')

    # OIDC subjects. Computed centrally so no template can invent its own.
    $map['computed.oidcSubjectPullRequest'] = "repo:${slug}:pull_request"
    $map['computed.oidcSubjectDefaultBranch'] = "repo:${slug}:ref:refs/heads/$($Config.github.defaultBranch)"
    $map['computed.oidcIssuer'] = 'https://token.actions.githubusercontent.com'
    $map['computed.oidcAudience'] = 'api://AzureADTokenExchange'

    # Backup redundancy is a boolean in the configuration and a provider enum in
    # Terraform. Translating here keeps the mapping in one place: a template that
    # emitted the boolean would produce `storage_redundancy = true`, which the
    # provider rejects only at apply.
    $map['computed.backupRedundancy'] = if ($Config.security.backup.geoRedundant) { 'GeoRedundant' } else { 'LocallyRedundant' }

    # Alert receivers are a list of {name, email_address} objects in Terraform
    # but a plain email list in the configuration. Composing them here
    # (decision record 0003) assigns each receiver a stable index-based name
    # and keeps the only permitted source — observability.alerting.
    # actionGroupEmails — in one place; no other contact list may feed Azure
    # Monitor enrollment. Optional keys are stripped from exported
    # configurations, so the existence checks come first (StrictMode).
    $alertReceivers = @()
    if ((Test-LzHasProperty $Config 'observability') -and
        (Test-LzHasProperty $Config.observability 'alerting') -and
        (Test-LzHasProperty $Config.observability.alerting 'actionGroupEmails')) {
        $emails = @($Config.observability.alerting.actionGroupEmails)
        for ($n = 0; $n -lt $emails.Count; $n++) {
            $alertReceivers += [pscustomobject]@{
                name          = ('receiver-{0:d2}' -f ($n + 1))
                email_address = $emails[$n]
            }
        }
    }
    $map['computed.alertEmailReceivers'] = $alertReceivers

    # Tag map rendered into every layer's default_tags.
    $map['computed.defaultTags'] = $Config.naming.defaultTags

    # The client's policy selection, resolved against the generated catalog into
    # the two variables the global layer inverts into
    # policy_assignments_to_modify.
    $policy = Resolve-LzPolicySelection -Config $Config
    $map['computed.policyAssignmentChanges'] = ConvertTo-LzHclPolicyChanges $policy.Changes
    $map['computed.policyAssignmentManagementGroups'] = ConvertTo-LzHclPolicyScopes $policy.Scopes
    $map['computed.policyAssignmentsChanged'] = $policy.Changes.Count
    $map['computed.policyAssignmentsCreated'] = $policy.CreatedCount
    $map['computed.policyAssignmentsTotal'] = $policy.TotalCount
    # Read through the resolver rather than off the configuration directly: the
    # values object is optional and an exported configuration strips it when the
    # client answered nothing, so a bare path read would throw on exactly the
    # estates that need no answer. Empty is legitimate — guard G28 is what
    # decides whether an empty value is a problem.
    $map['computed.policyValueDdosPlanId'] = $policy.Values['ddos_protection_plan_id']
    $map['computed.policyValueSecurityContact'] = $policy.Values['email_security_contact']

    # Management-group names. The pinned library owns the shape; the client may
    # own the names. Resolved once here so the emitted architecture definition,
    # the subscription placement targets and the documentation cannot disagree
    # about what a group is called — and management-group IDs are immutable, so
    # a disagreement is not something a later apply corrects.
    $groups = Resolve-LzManagementGroups -Config $Config
    $map['computed.hasCustomArchitecture'] = [bool]$groups.HasCustomArchitecture
    # Whether the sandbox management group is one this estate creates. Under
    # caf-minimal it is not, so the global layer must not be handed a placement
    # target that will never exist. Guard G31 refuses the combination that would
    # need one anyway.
    $map['computed.hasSandboxGroup'] = ('sandbox' -in $groups.EmittedGroupIds)
    $map['computed.architectureName'] = $groups.ArchitectureName
    $map['computed.managementGroupId'] = $groups.Effective['management'].id
    $map['computed.connectivityManagementGroupId'] = $groups.Effective['connectivity'].id
    $map['computed.identityManagementGroupId'] = $groups.Effective['identity'].id
    $map['computed.sandboxManagementGroupId'] = $groups.Effective['sandbox'].id
    $map['computed.workloadManagementGroupId'] = $groups.WorkloadGroupId
    $map['computed.alzLibraryPath'] = $groups.LibraryPath
    $map['computed.alzLibraryRef'] = $groups.LibraryRef

    # ── Answers that reach a document rather than a resource ─────────────────
    # These were collected, recorded in lz-config.json, and rendered nowhere:
    # the client answered and the repository they were handed said nothing about
    # it. Flattened into FOREACH-ready lists here, in the same idiom as the
    # brownfield dispositions above, because a template cannot join an array of
    # objects into a table on its own.
    #
    # Always present, empty rather than absent: an unknown token path THROWS at
    # render time, so a list that exists only when the client answered would
    # turn every #{{FOREACH}} over it into a render failure for everyone else.
    $approvals = [System.Collections.Generic.List[object]]::new()
    if ((Test-LzHasProperty $Config 'operations') -and (Test-LzHasProperty $Config.operations 'approvalChain')) {
        foreach ($stage in @($Config.operations.approvalChain)) {
            $approvals.Add([pscustomobject]@{
                stage        = [string]$stage.stage
                approvers    = (@($stage.approvers) -join ', ')
                environments = (@($stage.appliesToEnvironments) -join ', ')
            })
        }
    }
    $map['computed.approvalChain'] = @($approvals)
    $map['computed.hasApprovalChain'] = ($approvals.Count -gt 0)

    $budgets = [System.Collections.Generic.List[object]]::new()
    if ((Test-LzHasProperty $Config 'finops') -and (Test-LzHasProperty $Config.finops 'budgets')) {
        foreach ($budget in @($Config.finops.budgets)) {
            $budgets.Add([pscustomobject]@{
                scope      = [string]$budget.scope
                amount     = [string]$budget.amountUsd
                timeGrain  = [string]$budget.timeGrain
                # Rendered as percentages because that is how they are set and
                # how an alert reads; the raw integers would need explaining.
                thresholds = ((@($budget.alertThresholdPercents) | ForEach-Object { "$_%" }) -join ', ')
                contacts   = (@($budget.contactEmails) -join ', ')
            })
        }
    }
    $map['computed.finopsBudgets'] = @($budgets)
    $map['computed.hasFinopsBudgets'] = ($budgets.Count -gt 0)

    # $defs/contact objects, not strings — a FACTORY-LIST over the raw array
    # would render PSCustomObject type names into the handed-over document.
    # Phone is optional and deliberately included: the schema says it is used
    # only in generated contact tables and never transmitted, and this is that
    # table.
    $breakGlass = [System.Collections.Generic.List[object]]::new()
    if ((Test-LzHasProperty $Config 'operations') -and (Test-LzHasProperty $Config.operations 'breakGlassContacts')) {
        foreach ($contact in @($Config.operations.breakGlassContacts)) {
            $breakGlass.Add([pscustomobject]@{
                name  = [string]$contact.name
                email = [string]$contact.email
                role  = if (Test-LzHasProperty $contact 'role') { [string]$contact.role } else { '—' }
                phone = if (Test-LzHasProperty $contact 'phone') { [string]$contact.phone } else { '—' }
            })
        }
    }
    $map['computed.breakGlassContacts'] = @($breakGlass)
    $map['computed.hasBreakGlassContacts'] = ($breakGlass.Count -gt 0)

    # The non-prod spokes, as rows. Per ADR 0017 no layer builds a workload
    # spoke, so these describe an addressing decision the estate team implements
    # — which is exactly why writing them down is the whole of the fix.
    $spokes = [System.Collections.Generic.List[object]]::new()
    if ((Test-LzHasProperty $Config.connectivity 'hubSpoke') -and
        (Test-LzHasProperty $Config.connectivity.hubSpoke 'nonProdSpokeAddressSpaces')) {
        $spokeConfig = $Config.connectivity.hubSpoke.nonProdSpokeAddressSpaces
        foreach ($environment in @('dev', 'test', 'uat')) {
            if (-not (Test-LzHasProperty $spokeConfig $environment)) { continue }
            $entry = $spokeConfig.$environment
            $primary = if (Test-LzHasProperty $entry 'primary') { [string]$entry.primary } else { '' }
            $dr = if (Test-LzHasProperty $entry 'dr') { [string]$entry.dr } else { '' }
            if (-not $primary -and -not $dr) { continue }
            $spokes.Add([pscustomobject]@{
                environment = $environment
                primary     = if ($primary) { $primary } else { '—' }
                dr          = if ($dr) { $dr } else { '—' }
            })
        }
    }
    $map['computed.nonProdSpokes'] = @($spokes)
    $map['computed.hasNonProdSpokes'] = ($spokes.Count -gt 0)

    # Scalar answers that reach a document, resolved to a readable value here
    # rather than guarded at seventeen call sites in the templates.
    #
    # Every one of these keys is OPTIONAL, and an exported configuration STRIPS
    # an optional key rather than emitting it empty — so a bare {{FACTORY:...}}
    # throws "Unknown configuration path" for any client who left it blank. The
    # documented alternative is `#{{IF defined path}}` around each, which would
    # turn six readable tables into forty lines of conditionals. Resolving once
    # here keeps the templates flat and renders "not recorded" instead of a
    # blank cell, which is what the reader actually needs to know.
    $documented = [ordered]@{
        'docCostExportAccount'       = 'finops.costExports.storageAccountName'
        'docCostExportFrequency'     = 'finops.costExports.frequency'
        'docPlatformTeamSlug'        = 'operations.platformTeam.githubTeamSlug'
        'docSupportHours'            = 'operations.platformTeam.supportHours'
        'docEscalationUrl'           = 'operations.platformTeam.escalationUrl'
        'docIdentityStrategy'        = 'identity.strategy'
        'docSentinelRetention'       = 'security.sentinel.retentionDays'
        'docKeyVaultPurgeProtection' = 'security.keyVault.enablePurgeProtection'
        'docKeyVaultSoftDelete'      = 'security.keyVault.softDeleteRetentionDays'
        'docKeyVaultRbac'            = 'security.keyVault.enableRbacAuthorization'
        'docFlowLogRetention'        = 'security.nsgFlowLogs.retentionDays'
        'docTrafficAnalytics'        = 'security.nsgFlowLogs.trafficAnalytics'
        'docErCircuitName'           = 'connectivity.expressRoute.circuitName'
        'docErPeeringLocation'       = 'connectivity.expressRoute.peeringLocation'
        'docErBandwidthMbps'         = 'connectivity.expressRoute.bandwidthMbps'
        'docErServiceProvider'       = 'connectivity.expressRoute.serviceProvider'
        'docPrimaryHubAddressSpace'  = 'connectivity.hubSpoke.primaryHubAddressSpace'
    }
    foreach ($token in $documented.Keys) {
        $value = if ($map.Contains($documented[$token])) { $map[$documented[$token]] } else { $null }
        # A boolean false is a recorded answer, not an absent one, so only null
        # and empty string fall back.
        $map["computed.$token"] = if ($value -is [bool]) { if ($value) { 'yes' } else { 'no' } }
        elseif ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { 'not recorded' }
        else { [string]$value }
    }

    if ($Discovery) { $map['computed.discoveryAvailable'] = $true }
    else { $map['computed.discoveryAvailable'] = $false }

    [pscustomobject]@{
        Config = $Config
        Tokens = $map
        Keys   = @($map.Keys)
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Policy selection
# ══════════════════════════════════════════════════════════════════════════════

$script:LzPolicyCatalog = $null

function Get-LzPolicyCatalog {
    <#
    .SYNOPSIS
        The generated ALZ policy catalog, read once per session.
    .DESCRIPTION
        Produced by factory/ci/New-AlzPolicyCatalog.ps1 from the library ref
        pinned in factory-version.json, and verified against that ref by the
        ALZ policy catalog CI check. The renderer reads it rather than the
        library directly for the same reason the wizard does: rendering must
        work with no network, and the two must not be able to disagree about
        which management groups carry which assignment.
    #>
    if ($null -ne $script:LzPolicyCatalog) { return $script:LzPolicyCatalog }
    # factory/renderer/private -> the repository root.
    $path = Join-Path $PSScriptRoot '../../../site/alz-policy-catalog.json'
    if (-not (Test-Path $path)) {
        throw "The generated ALZ policy catalog is missing ($path). Run factory/ci/New-AlzPolicyCatalog.ps1."
    }
    $script:LzPolicyCatalog = Get-Content $path -Raw | ConvertFrom-Json -Depth 30
    return $script:LzPolicyCatalog
}

function Resolve-LzPolicySelection {
    <#
    .SYNOPSIS
        Turn the client's answers into deltas from the pinned library baseline.
    .DESCRIPTION
        Returns only assignments the client actually changed. An assignment with
        no entry is created exactly as the library declares it, which is what
        keeps a library bump from being silently narrowed by an older answer
        record — the same reason an absent group id means enabled.

        Three things can produce a delta:

          * a capability group the client turned off, or a per-assignment
            override, either of which yields creation_enabled = false;
          * a per-assignment enforcement override from the advanced list;
          * the baseline enforcement mode. Audit downgrades the assignments the
            catalog identifies as deny-class and nothing else. Applying it to
            every enforcing assignment would read more literally but would also
            stop DeployIfNotExists and Modify remediation across the estate —
            the Defender configuration, the Azure Monitor Agent, diagnostic
            settings and private-DNS registration this factory deploys would
            never converge. Deny-class is read from the assignment's declared
            effect at the pinned ref, widened by the ALZ naming convention for
            the ones whose effect lives in a built-in definition; erring that
            way costs enforcement, never remediation.
    #>
    param([Parameter(Mandatory)][object]$Config)

    $catalog = Get-LzPolicyCatalog
    $selection = $null
    if ((Test-LzHasProperty $Config 'governance') -and
        (Test-LzHasProperty $Config.governance 'policySelection')) {
        $selection = $Config.governance.policySelection
    }
    $groups = if ($selection -and (Test-LzHasProperty $selection 'groups')) { $selection.groups } else { $null }
    $overrides = if ($selection -and (Test-LzHasProperty $selection 'assignments')) { $selection.assignments } else { $null }

    $auditBaseline = $Config.governance.policyBaseline.enforcementMode -ne 'deny'

    # Assignment -> the group that claims it, so a group toggle can reach it.
    $groupOf = @{}
    foreach ($group in @($catalog.groups)) {
        foreach ($name in @($group.assignments)) { $groupOf[$name] = $group.id }
    }

    $changes = [ordered]@{}
    $scopes = [ordered]@{}
    $created = 0
    $createdNames = [System.Collections.Generic.List[string]]::new()

    foreach ($name in @(Get-LzPropertyNames $catalog.assignments | Sort-Object)) {
        $assignment = $catalog.assignments.$name
        $override = if ($overrides -and (Test-LzHasProperty $overrides $name)) { $overrides.$name } else { $null }

        # Creation: the per-assignment override wins over its group, and an
        # assignment no group claims is created.
        $enabled = $true
        if ($groupOf.ContainsKey($name) -and $groups -and (Test-LzHasProperty $groups $groupOf[$name])) {
            $enabled = [bool]$groups.($groupOf[$name])
        }
        if ($override -and (Test-LzHasProperty $override 'creationEnabled')) {
            $enabled = [bool]$override.creationEnabled
        }
        if ($enabled) { $created++; [void]$createdNames.Add($name) }

        # Enforcement: an explicit override wins; otherwise the audit baseline
        # reaches the deny-class assignments the library ships enforcing.
        $enforcement = $null
        if ($override -and (Test-LzHasProperty $override 'enforcementMode') -and $override.enforcementMode) {
            $enforcement = [string]$override.enforcementMode
        }
        elseif ($auditBaseline -and $assignment.denyClass -and $assignment.libraryEnforcementMode -eq 'Default') {
            $enforcement = 'DoNotEnforce'
        }

        $change = [ordered]@{}
        # Only deltas travel: an assignment the library already creates needs no
        # entry, and neither does an enforcement mode it already has. An
        # assignment that is never created has no enforcement mode to state.
        if (-not $enabled) { $change['creation_enabled'] = $false }
        elseif ($enforcement -and $enforcement -ne $assignment.libraryEnforcementMode) {
            $change['enforcement_mode'] = $enforcement
        }
        if ($change.Count -eq 0) { continue }

        $changes[$name] = $change
        $scopes[$name] = @($assignment.managementGroups)
    }

    # The client-owned default values, normalised so an absent object, an absent
    # key and a blank answer are the same thing to every consumer.
    $answered = [ordered]@{}
    $values = if ($selection -and (Test-LzHasProperty $selection 'values')) { $selection.values } else { $null }
    foreach ($name in @(Get-LzPropertyNames $catalog.defaults)) {
        $answer = ''
        if ($values -and (Test-LzHasProperty $values $name)) { $answer = ([string]$values.$name).Trim() }
        $answered[$name] = $answer
    }

    [pscustomobject]@{
        Values             = $answered
        Changes            = $changes
        Scopes             = $scopes
        CreatedCount       = $created
        CreatedAssignments = @($createdNames)
        TotalCount         = @(Get-LzPropertyNames $catalog.assignments).Count
    }
}

function Resolve-LzManagementGroups {
    <#
    .SYNOPSIS
        The management groups this estate will create, after the client's renames.
    .DESCRIPTION
        The `custom` hierarchy strategy renames the groups the pinned ALZ library
        architecture defines. It does not re-shape them, and the distinction is
        the whole design: an archetype is attached to a management group by the
        architecture definition, so moving a group under a different parent
        changes which policy set governs everything beneath it. Management-group
        IDs are immutable in Azure, which makes that a one-way mistake per
        client — the reason 6.4's scope is names first.

        `caf-minimal` is the one strategy that changes the SHAPE rather than the
        names: it drops the two groups the standard hierarchy carries outside
        Platform and Landing Zones. It emits its own architecture definition for
        the same reason `custom` does — the pinned library has no trimmed
        architecture to select.

        Returns the effective id and display name for every library group, which
        of them are actually emitted, the architecture name to select, and the
        group the workload subscriptions land in.
    #>
    param([Parameter(Mandatory)][object]$Config)

    $catalog = Get-LzPolicyCatalog
    $mg = $Config.azure.managementGroups
    $isCustom = ($mg.strategy -eq 'custom')
    $isMinimal = ($mg.strategy -eq 'caf-minimal')
    $renames = if ($isCustom -and (Test-LzHasProperty $mg 'customHierarchy')) { $mg.customHierarchy } else { $null }

    # "Platform + Landing Zones only" — the schema's own description of
    # caf-minimal, which until 2026-08-31 described nothing the factory did.
    #
    # These two and no others, and the choice is forced rather than a matter of
    # taste. Both are direct children of the root with NO CHILDREN OF THEIR OWN,
    # so dropping them re-parents nothing; every other library group is either
    # Platform, Landing Zones, or a child of one of those two. Dropping Corp or
    # Online instead would strand azure.managementGroups.workloadPlacement,
    # which is exactly why 6.4a was left open rather than guessed at.
    $dropped = if ($isMinimal) { @('sandbox', 'decommissioned') } else { @() }

    $effective = @{}
    foreach ($group in @($catalog.managementGroups)) {
        $id = [string]$group.id
        $displayName = [string]$group.displayName
        if ($renames -and (Test-LzHasProperty $renames $group.id)) {
            $rename = $renames.($group.id)
            if ((Test-LzHasProperty $rename 'id') -and ([string]$rename.id).Trim()) { $id = ([string]$rename.id).Trim() }
            if ((Test-LzHasProperty $rename 'displayName') -and ([string]$rename.displayName).Trim()) {
                $displayName = ([string]$rename.displayName).Trim()
            }
        }
        $effective[$group.id] = @{ id = $id; displayName = $displayName; parent = [string]$group.parent; archetypes = @($group.archetypes) }
    }

    # Where workload subscriptions land. corp and online are the ALZ landing-zone
    # children; landingzones places directly and forecloses telling them apart
    # later without moving the subscription.
    $placement = if (Test-LzHasProperty $mg 'workloadPlacement') { [string]$mg.workloadPlacement } else { 'corp' }
    if (-not $effective.ContainsKey($placement)) { $placement = 'landingzones' }

    $factoryVersionPath = Join-Path $PSScriptRoot '../../../factory-version.json'
    $pinned = Get-Content $factoryVersionPath -Raw | ConvertFrom-Json -Depth 20

    $short = ([string]$Config.organization.companyShortName).ToLowerInvariant()

    [pscustomobject]@{
        IsCustom         = $isCustom
        IsMinimal        = $isMinimal
        # Both strategies that depart from the pinned library's own architecture
        # need a local definition emitted and library_references pointed at it.
        # Renaming groups and dropping groups are the same problem to the
        # provider: the architecture it is asked for is not one the library has.
        HasCustomArchitecture = ($isCustom -or $isMinimal)
        # The architecture name doubles as the emitted library file's basename,
        # so it has to be a safe identifier rather than a display string.
        ArchitectureName = if ($isCustom) { $short } elseif ($isMinimal) { "$short-minimal" } else { $catalog.library.architecture }
        Effective        = $effective
        # Every library group keeps an entry in Effective so the computed.*
        # tokens that name one still resolve; EmittedGroupIds is what decides
        # which are actually created.
        EmittedGroupIds  = @(@($catalog.managementGroups | ForEach-Object { [string]$_.id }) | Where-Object { $_ -notin $dropped })
        DroppedGroupIds  = @($dropped)
        WorkloadGroupId  = $effective[$placement].id
        WorkloadLibraryId = $placement
        LibraryPath      = [string]$pinned.avm.alzLibrary.path
        LibraryRef       = [string]$pinned.avm.alzLibrary.ref
    }
}

function New-LzAlzArchitectureDefinition {
    <#
    .SYNOPSIS
        The client-named architecture definition, in the library's own format.
    .DESCRIPTION
        A flat management-group list carrying parent_id — not a nested tree.
        Reading it as nested yields a plausible-looking hierarchy in which
        everything is a child of the root, which is why this mirrors the pinned
        library's shape edge for edge and only substitutes names.
    #>
    param([Parameter(Mandatory)][object]$Config)

    $groups = Resolve-LzManagementGroups -Config $Config
    $catalog = Get-LzPolicyCatalog

    $managementGroups = foreach ($group in @($catalog.managementGroups)) {
        # caf-minimal drops groups; a dropped group must not be emitted, and
        # nothing under the standard hierarchy parents to one, so no child is
        # orphaned by the omission.
        if ([string]$group.id -notin $groups.EmittedGroupIds) { continue }
        $current = $groups.Effective[$group.id]
        # The parent edge travels renamed too, or a renamed parent would leave
        # its children pointing at a group that is never created.
        $parent = if ($current.parent -and $groups.Effective.ContainsKey($current.parent)) {
            $groups.Effective[$current.parent].id
        }
        else { $null }
        [ordered]@{
            archetypes   = @($current.archetypes)
            display_name = $current.displayName
            exists       = $false
            id           = $current.id
            parent_id    = $parent
        }
    }

    [ordered]@{
        '$schema'         = 'https://raw.githubusercontent.com/Azure/Azure-Landing-Zones-Library/main/schemas/architecture_definition.json'
        name              = $groups.ArchitectureName
        management_groups = @($managementGroups)
    }
}

function ConvertTo-LzHclPolicyChanges {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Changes)
    if ($Changes.Count -eq 0) { return '{}' }
    $lines = foreach ($name in $Changes.Keys) {
        $body = foreach ($attribute in $Changes[$name].Keys) {
            $value = $Changes[$name][$attribute]
            $literal = if ($value -is [bool]) { ConvertTo-LzBoolLiteral $value } else { ConvertTo-LzHclString $value }
            "      $attribute = $literal"
        }
        "  $(ConvertTo-LzHclString $name) = {`n" + ($body -join "`n") + "`n  }"
    }
    return "{`n" + ($lines -join "`n") + "`n}"
}

function ConvertTo-LzHclPolicyScopes {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Scopes)
    if ($Scopes.Count -eq 0) { return '{}' }
    $lines = foreach ($name in $Scopes.Keys) {
        "  $(ConvertTo-LzHclString $name) = $(ConvertTo-LzHclList $Scopes[$name])"
    }
    return "{`n" + ($lines -join "`n") + "`n}"
}

function Get-LzActiveLayers {
    <#
    .SYNOPSIS
        Determine which terraform/live layers this configuration emits.
    .DESCRIPTION
        Layers are never merged. Each is its own state file, workspace, and
        environment gate — collapsing two layers into one state is the single
        most common way a landing zone becomes unrecoverable, so the renderer
        treats the layer list as fixed structure rather than a preference
        (control AR3).
    #>
    param([Parameter(Mandatory)][object]$Config)

    # The AVM architecture emits exactly three layers (ADR 0013/0017).
    # Order is the deploy order: platform-management first, because the global
    # layer reads its state for the Log Analytics policy default. Workload
    # spokes and sandboxes are per-estate work done inside the generated
    # repository, not generator architecture.
    $layers = @('platform-management', 'global')

    if ($Config.connectivity.model -ne 'none') { $layers += 'platform-connectivity' }

    # Stage-2 state hardening (ADR 0019): a private endpoint for the state
    # storage account, emitted only when explicitly requested. Deliberately
    # LAST: it needs the hub (platform-connectivity) applied first, and guard
    # G27 refuses the flag without hub-spoke + centralized private DNS +
    # self-hosted runners.
    #
    # It is also azurerm-only, structurally: the layer reads the state storage
    # account as a data source and puts a private endpoint in front of it. Under
    # the HCP Terraform backend there is no storage account to harden, so the
    # layer would emit a data source pointing at nothing. Guard G17 refuses the
    # combination rather than letting it render.
    $pe = $null
    if ((Test-LzHasProperty $Config.backend 'azurerm') -and
        (Test-LzHasProperty $Config.backend.azurerm 'privateEndpoint')) {
        $pe = $Config.backend.azurerm.privateEndpoint
    }
    $backendType = if (Test-LzHasProperty $Config.backend 'type') { [string]$Config.backend.type } else { 'azurerm' }
    if ($backendType -eq 'azurerm' -and $pe -and (Test-LzHasProperty $pe 'enabled') -and $pe.enabled) {
        $layers += 'state-hardening'
    }

    return $layers
}

function Test-LzIsComposite {
    <#
    .SYNOPSIS
        True when a value is an object with named properties worth recursing into.
    .DESCRIPTION
        Explicit type dispatch, not property sniffing. Under Set-StrictMode,
        reaching for .PSObject.Properties.Count on a primitive throws, and
        `$x -is [psobject]` is true for literally every value in PowerShell —
        so the obvious-looking check is both wrong and fatal.
    #>
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $false }
    return ($Value -is [System.Management.Automation.PSCustomObject] -or
            $Value -is [System.Collections.IDictionary])
}

function Get-LzPropertyNames {
    <#
    .SYNOPSIS
        Property names of a composite value, or an empty array.
    #>
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) { return @($Value.Keys) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        return @($Value.PSObject.Properties | ForEach-Object { $_.Name })
    }
    return @()
}

function Test-LzHasProperty {
    <#
    .SYNOPSIS
        Null-safe, StrictMode-safe property existence test.
    #>
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    return ((Get-LzPropertyNames $Value) -contains $Name)
}

function Add-LzSchemaDefault {
    <#
    .SYNOPSIS
        Seed schema-declared defaults for optional keys the configuration omits.
    .DESCRIPTION
        The flattener can only produce paths the configuration document
        actually contains, so an OPTIONAL key with a schema `default` resolved
        to "Unknown configuration path" and the render failed closed — on a
        configuration the schema itself considers valid. The observed case was
        a `backend.azurerm` block without `useAzureAdAuth` (schema default
        true), which four templates reference.

        Gating the reference sites individually would have fixed that one key
        and left the class open for the next optional-with-default key anyone
        adds. Seeding here fixes it once, for every such key.

        A default is only seeded when its PARENT path already resolves. Without
        that guard, an absent `backend.azurerm` block would still materialise
        `backend.azurerm.useAzureAdAuth`, inventing a path for a block the
        configuration never selected.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Target,
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix,
        [Parameter(Mandatory)][object]$Root
    )

    if (-not ($Node.PSObject.Properties.Name -contains 'properties')) { return }

    foreach ($property in $Node.properties.PSObject.Properties) {
        $path = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
        $child = $property.Value

        # Resolve $ref so shared definitions carry their defaults too.
        if ($child.PSObject.Properties.Name -contains '$ref') {
            $refName = ($child.'$ref' -replace '^#/\$defs/', '')
            if ($Root.PSObject.Properties.Name -contains '$defs' -and
                $Root.'$defs'.PSObject.Properties.Name -contains $refName) {
                $child = $Root.'$defs'.$refName
            }
        }

        if (-not $Target.Contains($path)) {
            $parentResolves = (-not $Prefix) -or $Target.Contains($Prefix)
            if ($parentResolves -and ($child.PSObject.Properties.Name -contains 'default')) {
                $Target[$path] = $child.default
            }
        }

        if ($child.PSObject.Properties.Name -contains 'properties') {
            Add-LzSchemaDefault -Target $Target -Node $child -Prefix $path -Root $Root
        }
    }
}

function Add-LzFlattenedObject {
    <#
    .SYNOPSIS
        Recursively flatten an object into dotted-path keys.
    .DESCRIPTION
        Arrays and maps are stored whole under their own path so that
        {{FACTORY-LIST:...}} and {{FACTORY-MAP:...}} can render them; items
        inside arrays are additionally addressable positionally.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Target,
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix
    )

    if ($null -eq $Object) { return }

    foreach ($name in (Get-LzPropertyNames $Object)) {
        $path = if ($Prefix) { "$Prefix.$name" } else { $name }
        $value = if ($Object -is [System.Collections.IDictionary]) { $Object[$name] } else { $Object.$name }

        if ($null -eq $value) { $Target[$path] = $null; continue }

        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string] -and
            $value -isnot [System.Collections.IDictionary]) {
            $items = @($value)
            $Target[$path] = $items
            for ($i = 0; $i -lt $items.Count; $i++) {
                $item = $items[$i]
                if (Test-LzIsComposite $item) {
                    Add-LzFlattenedObject -Target $Target -Object $item -Prefix "$path[$i]"
                    $Target["$path[$i]"] = $item
                }
                else { $Target["$path[$i]"] = $item }
            }
            continue
        }

        if (Test-LzIsComposite $value) {
            $Target[$path] = $value
            Add-LzFlattenedObject -Target $Target -Object $value -Prefix $path
            continue
        }

        $Target[$path] = $value
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Value formatting
# ══════════════════════════════════════════════════════════════════════════════

function ConvertTo-LzHclString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '""' }
    return (ConvertTo-Json -InputObject ([string]$Value) -Compress)
}

function ConvertTo-LzHclList {
    param([AllowNull()][object]$Value)
    # The outer @() is required: a pipeline that filters everything out yields
    # $null, not an empty array, and .Count on $null throws under StrictMode.
    $items = @(@($Value) | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return '[]' }
    return '[' + (($items | ForEach-Object { ConvertTo-LzHclString $_ }) -join ', ') + ']'
}

function ConvertTo-LzHclMap {
    <#
    .SYNOPSIS
        Render an object as an HCL map body.
    #>
    param([AllowNull()][object]$Value, [string]$Indent = '  ')
    if ($null -eq $Value) { return '{}' }

    $names = @(Get-LzPropertyNames $Value)
    if ($names.Count -eq 0) { return '{}' }

    $lines = $names | ForEach-Object {
        $n = $_
        $v = if ($Value -is [System.Collections.IDictionary]) { $Value[$n] } else { $Value.$n }
        # Keys needing quoting (dots, dashes) are quoted; bare identifiers are not.
        $key = if ($n -match '^[A-Za-z_][A-Za-z0-9_]*$') { $n } else { ConvertTo-LzHclString $n }
        "$Indent  $key = $(ConvertTo-LzHclString $v)"
    }
    return "{`n" + ($lines -join "`n") + "`n$Indent}"
}

function ConvertTo-LzBoolLiteral {
    param([AllowNull()][object]$Value)
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($null -eq $Value) { return 'false' }
    $s = [string]$Value
    if ($s -in @('true', 'True', '1', 'yes')) { return 'true' }
    return 'false'
}

# ══════════════════════════════════════════════════════════════════════════════
#  Expression evaluation
# ══════════════════════════════════════════════════════════════════════════════

function Test-LzExpression {
    <#
    .SYNOPSIS
        Evaluate a conditional directive expression against the render context.
    .DESCRIPTION
        The grammar is intentionally tiny, and kept that way on purpose: a
        template language that grows an expression engine becomes a program
        nobody reviews. Supported forms:

            path                          truthy test (throws if path unknown)
            !path                         negation
            defined path                  existence test (never throws)
            !defined path                 absence test
            path == 'value'               equality
            path != 'value'               inequality
            path contains 'value'         membership in an array or substring
            <expr> && <expr>              conjunction
            <expr> || <expr>              disjunction

        Unknown paths throw rather than evaluating false, so a renamed config
        key surfaces as a build error instead of silently removing a block of
        Terraform.

        `defined` is the deliberate exception, and exists because optional keys
        are STRIPPED from an exported configuration rather than emitted as
        empty. A template asking "was an identity subscription supplied?" is
        asking about existence, and must not fail merely because the answer is
        no. Use `defined` for genuinely optional keys and a bare path
        everywhere else — a bare path keeps typos loud, which is the behaviour
        that protects against silently dropping a block of Terraform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Expression,
        [Parameter(Mandatory)][object]$Context
    )

    $expr = $Expression.Trim()
    if (-not $expr) { throw 'Empty conditional expression.' }

    # Disjunction binds loosest.
    if ($expr -match '\|\|') {
        foreach ($part in ($expr -split '\|\|')) {
            if (Test-LzExpression -Expression $part -Context $Context) { return $true }
        }
        return $false
    }
    if ($expr -match '&&') {
        foreach ($part in ($expr -split '&&')) {
            if (-not (Test-LzExpression -Expression $part -Context $Context)) { return $false }
        }
        return $true
    }

    # Existence tests come before the general forms so `defined` is never
    # mistaken for a path segment.
    if ($expr -match '^!\s*defined\s+(?<path>[A-Za-z0-9_.\[\]-]+)$') {
        return -not (Test-LzPathDefined -Context $Context -Path $Matches['path'])
    }
    if ($expr -match '^defined\s+(?<path>[A-Za-z0-9_.\[\]-]+)$') {
        return (Test-LzPathDefined -Context $Context -Path $Matches['path'])
    }

    if ($expr -match "^(?<path>[A-Za-z0-9_.\[\]-]+)\s+contains\s+'(?<val>[^']*)'$") {
        $actual = Get-LzTokenValue -Context $Context -Path $Matches['path']
        $needle = $Matches['val']
        if ($null -eq $actual) { return $false }
        if ($actual -is [string]) { return $actual.Contains($needle) }
        return (@($actual) -contains $needle)
    }

    if ($expr -match "^(?<path>[A-Za-z0-9_.\[\]-]+)\s*(?<op>==|!=)\s*'(?<val>[^']*)'$") {
        $actual = Get-LzTokenValue -Context $Context -Path $Matches['path']
        $actualStr = if ($null -eq $actual) { '' } else { [string]$actual }
        $equal = ($actualStr -eq $Matches['val'])
        return $(if ($Matches['op'] -eq '==') { $equal } else { -not $equal })
    }

    if ($expr -match '^!\s*(?<path>[A-Za-z0-9_.\[\]-]+)$') {
        return -not (Test-LzTruthy (Get-LzTokenValue -Context $Context -Path $Matches['path']))
    }

    if ($expr -match '^(?<path>[A-Za-z0-9_.\[\]-]+)$') {
        return Test-LzTruthy (Get-LzTokenValue -Context $Context -Path $Matches['path'])
    }

    throw "Unsupported conditional expression: '$Expression'. Supported forms: path, !path, defined path, !defined path, path == 'v', path != 'v', path contains 'v', and && / || between them."
}

function Test-LzTruthy {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return (@($Value).Count -gt 0) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return ($Value -ne 0) }
    return $true
}

function Test-LzPathDefined {
    <#
    .SYNOPSIS
        True when a path exists in the render context and is not null.
    .DESCRIPTION
        Never throws. Backs the `defined` operator, which templates use to ask
        whether an optional key was supplied. An empty string counts as defined;
        combine with a bare path (`defined x && x`) when emptiness matters.
    #>
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Path
    )
    if (-not $Context.Tokens.Contains($Path)) { return $false }
    return ($null -ne $Context.Tokens[$Path])
}

function Get-LzTokenValue {
    <#
    .SYNOPSIS
        Resolve a dotted path in the render context, throwing on unknown keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Context.Tokens.Contains($Path)) { return $Context.Tokens[$Path] }

    # Fail closed, and make the failure diagnosable: suggest near-misses rather
    # than only reporting that the key is unknown.
    $suggestions = @(
        $Context.Keys | Where-Object {
            $_ -like "*$($Path.Split('.')[-1])*" -or $Path -like "*$($_.Split('.')[-1])*"
        } | Select-Object -First 5
    )
    $hint = if ($suggestions.Count) { " Did you mean: $($suggestions -join ', ')?" } else { '' }
    throw "Unknown configuration path '$Path'.$hint"
}
