#Requires -Version 7.0
<#
    Azure resource-plane discovery — read-only.

    This is the probe set that decides greenfield versus brownfield in practice.
    A tenant the operator believes is empty routinely contains a partial
    management group hierarchy, an orphaned policy assignment, or a VNet with an
    address space that collides with the planned hub.

    Every list operation below is scoped and bounded. `az graph query` is used
    where a tenant-wide sweep is genuinely needed, because per-subscription
    iteration across a large tenant is slow enough that operators skip discovery
    entirely — and a discovery step that gets skipped provides no safety at all.
#>

Set-StrictMode -Version Latest

# Cached once per session; $null means 'not yet checked'. Declared at script
# scope because Set-StrictMode rejects reading an undeclared variable.
$script:LzGraphExtensionPresent = $null

function Get-LzAzureInventory {
    <#
    .SYNOPSIS
        Inventory Azure management groups, subscriptions, and platform resources.
    .PARAMETER SubscriptionIds
        Subscriptions named in lz-config.json. Probed individually for existence
        and access.
    .PARAMETER ManagementGroupRootId
        The MG the hierarchy will be rooted under.
    .PARAMETER PlannedAddressSpaces
        Hub/spoke CIDRs from the configuration. Existing VNets are checked for
        overlap against these — a collision discovered here costs minutes; the
        same collision discovered at apply costs a redeployment.
    #>
    [CmdletBinding()]
    param(
        [string[]]$SubscriptionIds = @(),
        [string]$ManagementGroupRootId = '',
        [string[]]$PlannedAddressSpaces = @()
    )

    Write-LzSection 'Azure discovery'
    $probes = [ordered]@{}

    # ── Subscriptions visible to the operator ────────────────────────────────
    $probes['Accessible subscriptions'] = Invoke-LzProbe -Name 'Accessible subscriptions' -ForbiddenRemediation `
        'Run: az login' -Probe {
        $subs = Invoke-LzAz account list --all --query '[].{Name:name,Id:id,State:state,TenantId:tenantId}'
        if (-not $subs) { return @() }
        @($subs)
    }

    # ── Configured subscriptions: do they exist and are they reachable? ──────
    if ($SubscriptionIds.Count -gt 0) {
        $probes['Configured subscriptions'] = Invoke-LzProbe -Name 'Configured subscriptions' -Probe {
            $accessible = @()
            $accProbe = $probes['Accessible subscriptions']
            if ($accProbe.Status -eq 'Ok') { $accessible = @($accProbe.Items | ForEach-Object { $_.Id }) }

            @($SubscriptionIds | Where-Object { $_ } | Select-Object -Unique | ForEach-Object {
                $id = $_
                [pscustomobject]@{
                    SubscriptionId = $id
                    Accessible     = ($id -in $accessible)
                    Note           = if ($id -in $accessible) { '' }
                                     else { 'Not visible to the signed-in account. Either the ID is wrong or the operator lacks access — the deployment will fail at plan time.' }
                }
            })
        }
    }

    # ── Management group hierarchy ───────────────────────────────────────────
    $probes['Management groups'] = Invoke-LzProbe -Name 'Management groups' -ForbiddenRemediation `
        'Cannot enumerate management groups. Greenfield hierarchy creation requires write access at the root scope; see docs/factory/FACTORY-DESIGN.md assumption A7 for the intermediate-root alternative.' -Probe {
        $mgs = Invoke-LzAz account management-group list --query '[].{Name:name,DisplayName:displayName,Id:id}'
        if (-not $mgs) { return @() }
        @($mgs)
    }

    if ($ManagementGroupRootId) {
        $probes['Target root management group'] = Invoke-LzProbe -Name 'Target root management group' -Probe {
            $out = & az account management-group show --name $ManagementGroupRootId --query '{Name:name,DisplayName:displayName,Id:id}' 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                if ($out -match 'NotFound|could not be found|ResourceNotFound') { return @() }
                throw $out.Trim()
            }
            @($out | ConvertFrom-Json -Depth 10)
        }
    }

    # ── Resource Graph sweeps ────────────────────────────────────────────────
    # One query each, tenant-wide, rather than N subscription iterations.

    $probes['Virtual networks'] = Invoke-LzProbe -Name 'Virtual networks' -ForbiddenRemediation `
        'Cannot query Azure Resource Graph. Grant Reader at the scopes being assessed and ensure the extension is present (az extension add --name resource-graph); without this, an address-space collision cannot be detected before apply.' -Probe {
        $q = "Resources | where type =~ 'microsoft.network/virtualnetworks' | project name, resourceGroup, subscriptionId, location, addressPrefixes = properties.addressSpace.addressPrefixes | limit 500"
        $r = Invoke-LzGraphQuery -Query $q -First 500
        if (-not $r -or -not $r.data) { return @() }
        @($r.data | ForEach-Object {
            [pscustomobject]@{
                Name           = $_.name
                ResourceGroup  = $_.resourceGroup
                SubscriptionId = $_.subscriptionId
                Location       = $_.location
                AddressPrefixes = (@($_.addressPrefixes) -join ', ')
            }
        })
    }

    $probes['Resource groups'] = Invoke-LzProbe -Name 'Resource groups' -Probe {
        $q = "ResourceContainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | project name, subscriptionId, location | limit 500"
        $r = Invoke-LzGraphQuery -Query $q -First 500
        if (-not $r -or -not $r.data) { return @() }
        @($r.data | ForEach-Object {
            [pscustomobject]@{ Name = $_.name; SubscriptionId = $_.subscriptionId; Location = $_.location }
        })
    }

    $probes['Log Analytics workspaces'] = Invoke-LzProbe -Name 'Log Analytics workspaces' -Probe {
        $q = "Resources | where type =~ 'microsoft.operationalinsights/workspaces' | project name, resourceGroup, subscriptionId, location, sku = properties.sku.name, retentionInDays = properties.retentionInDays | limit 200"
        $r = Invoke-LzGraphQuery -Query $q -First 200
        if (-not $r -or -not $r.data) { return @() }
        @($r.data | ForEach-Object {
            [pscustomobject]@{
                Name = $_.name; ResourceGroup = $_.resourceGroup; SubscriptionId = $_.subscriptionId
                Location = $_.location; Sku = $_.sku; RetentionDays = $_.retentionInDays
            }
        })
    }

    $probes['Key vaults'] = Invoke-LzProbe -Name 'Key vaults' -Probe {
        $q = "Resources | where type =~ 'microsoft.keyvault/vaults' | project name, resourceGroup, subscriptionId, location, enablePurgeProtection = properties.enablePurgeProtection, enableRbac = properties.enableRbacAuthorization | limit 200"
        $r = Invoke-LzGraphQuery -Query $q -First 200
        if (-not $r -or -not $r.data) { return @() }
        @($r.data | ForEach-Object {
            [pscustomobject]@{
                Name = $_.name; ResourceGroup = $_.resourceGroup; SubscriptionId = $_.subscriptionId
                PurgeProtection = $_.enablePurgeProtection; RbacAuthorization = $_.enableRbac
            }
        })
    }

    # ── Governance ───────────────────────────────────────────────────────────
    $probes['Policy assignments'] = Invoke-LzProbe -Name 'Policy assignments' -ForbiddenRemediation `
        'Cannot list policy assignments. Existing Deny policies are the most common cause of a first apply failing in a tenant believed to be empty.' -Probe {
        $pa = Invoke-LzAz policy assignment list --disable-scope-strict-match `
            --query '[].{Name:name,DisplayName:displayName,Scope:scope,EnforcementMode:enforcementMode,PolicyDefinitionId:policyDefinitionId}'
        if (-not $pa) { return @() }
        @($pa)
    }

    $probes['Custom policy definitions'] = Invoke-LzProbe -Name 'Custom policy definitions' -Probe {
        # Filtered in PowerShell rather than with a JMESPath --query: values
        # containing [? ] and quotes are re-parsed unreliably by the az.cmd shim
        # on Windows, and a discovery step that fails only on one OS is worse
        # than no discovery step at all.
        $pd = Invoke-LzAz policy definition list
        if (-not $pd) { return @() }
        @($pd | Where-Object { $_.policyType -eq 'Custom' } | ForEach-Object {
            [pscustomobject]@{ Name = $_.name; DisplayName = $_.displayName; Mode = $_.mode }
        })
    }

    $probes['Role assignments (current user)'] = Invoke-LzProbe -Name 'Role assignments (current user)' -Probe {
        $principalId = Get-LzCurrentPrincipalId
        if (-not $principalId) {
            # Without a principal ID the query would silently list nothing, which
            # would read as "this account holds no roles" — a materially wrong
            # conclusion. Fail loudly instead.
            throw 'Could not resolve the signed-in principal ID, so role assignments could not be listed.'
        }
        $ra = Invoke-LzAz role assignment list --all --assignee-object-id $principalId `
            --query '[].{Role:roleDefinitionName,Scope:scope,PrincipalType:principalType}'
        if (-not $ra) { return @() }
        @($ra)
    }

    # ── Security posture ─────────────────────────────────────────────────────
    $probes['Defender for Cloud plans'] = Invoke-LzProbe -Name 'Defender for Cloud plans' -Probe {
        $sub = Get-LzDefaultSubscriptionId
        if (-not $sub) { return @() }
        $resp = Invoke-LzAz rest --method get --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Security/pricings?api-version=2023-01-01"
        if (-not $resp -or -not $resp.value) { return @() }
        @($resp.value | Where-Object { $_.properties.pricingTier -eq 'Standard' } | ForEach-Object {
            [pscustomobject]@{ Plan = $_.name; Tier = $_.properties.pricingTier; SubPlan = if ($_.properties.PSObject.Properties.Name -contains 'subPlan') { $_.properties.subPlan } else { '' } }
        })
    }

    $probes['Sentinel workspaces'] = Invoke-LzProbe -Name 'Sentinel workspaces' -Probe {
        $q = "Resources | where type =~ 'microsoft.operationsmanagement/solutions' and name startswith 'SecurityInsights' | project name, resourceGroup, subscriptionId | limit 100"
        $r = Invoke-LzGraphQuery -Query $q -First 100
        if (-not $r -or -not $r.data) { return @() }
        @($r.data | ForEach-Object {
            [pscustomobject]@{ Solution = $_.name; ResourceGroup = $_.resourceGroup; SubscriptionId = $_.subscriptionId }
        })
    }

    foreach ($p in $probes.Values) { Write-LzProbeResult $p }

    # ── Address-space collision analysis ─────────────────────────────────────
    $collisions = @()
    if ($PlannedAddressSpaces.Count -gt 0 -and $probes['Virtual networks'].Status -eq 'Ok') {
        $collisions = Get-LzAddressSpaceCollision `
            -PlannedCidrs $PlannedAddressSpaces `
            -ExistingVNets $probes['Virtual networks'].Items
        foreach ($c in $collisions) {
            Write-LzWarn ("Address space {0} overlaps existing VNet '{1}' ({2})" -f $c.PlannedCidr, $c.VNetName, $c.ExistingCidr)
        }
    }

    [pscustomobject]@{
        Domain                = 'Azure'
        ManagementGroupRootId = $ManagementGroupRootId
        Probes                = $probes
        AddressCollisions     = $collisions
        ExistingLandingZone   = Test-LzExistingLandingZone -Probes $probes
    }
}

function Invoke-LzGraphQuery {
    <#
    .SYNOPSIS
        Run an Azure Resource Graph query, with an actionable error when the
        resource-graph extension is missing.
    .DESCRIPTION
        Without the extension, `az graph` emits a dynamic-install warning and
        exits non-zero. Surfacing that raw is unhelpful: the operator sees a
        warning about extension preview policy rather than the one command that
        fixes it. We check once and throw a message the classifier routes to
        Unavailable with a usable remediation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$First = 500
    )

    if ($null -eq $script:LzGraphExtensionPresent) {
        $script:LzGraphExtensionPresent = Test-LzAzExtension -Name 'resource-graph'
    }
    if (-not $script:LzGraphExtensionPresent) {
        throw "The Azure CLI 'resource-graph' extension is not installed, so tenant-wide inventory could not run. Install it with: az extension add --name resource-graph"
    }

    return Invoke-LzAz graph query -q $Query --first $First
}

function Get-LzCurrentPrincipalId {
    <#
    .SYNOPSIS
        Object ID of the signed-in principal, or empty string if unavailable.
    #>
    try { return (Invoke-LzAzRaw ad signed-in-user show --query id -o tsv) }
    catch { return '' }
}

function Get-LzDefaultSubscriptionId {
    try { return (Invoke-LzAzRaw account show --query id -o tsv) }
    catch { return '' }
}

function Get-LzAddressSpaceCollision {
    <#
    .SYNOPSIS
        Find overlaps between planned CIDRs and existing VNet address prefixes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$PlannedCidrs,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExistingVNets
    )

    $out = @()
    foreach ($planned in ($PlannedCidrs | Where-Object { $_ })) {
        foreach ($vnet in $ExistingVNets) {
            foreach ($existing in ($vnet.AddressPrefixes -split ',\s*' | Where-Object { $_ })) {
                if (Test-LzCidrOverlap -CidrA $planned -CidrB $existing) {
                    $out += [pscustomobject]@{
                        PlannedCidr    = $planned
                        VNetName       = $vnet.Name
                        ExistingCidr   = $existing
                        SubscriptionId = $vnet.SubscriptionId
                        ResourceGroup  = $vnet.ResourceGroup
                    }
                }
            }
        }
    }
    return $out
}

function Test-LzCidrOverlap {
    <#
    .SYNOPSIS
        True when two IPv4 CIDR ranges intersect.
    #>
    param(
        [Parameter(Mandatory)][string]$CidrA,
        [Parameter(Mandatory)][string]$CidrB
    )

    # All arithmetic is done in int64. PowerShell's -bnot on a uint32 yields a
    # signed value, so staying in uint32 produces a negative broadcast address
    # and a conversion error; int64 holds the full 32-bit range unsigned.
    function ConvertTo-Range([string]$cidr) {
        if ($cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') { return $null }
        $ip = $Matches[1]; $bits = [int]$Matches[2]
        if ($bits -lt 0 -or $bits -gt 32) { return $null }

        $octets = @($ip -split '\.' | ForEach-Object { [int]$_ })
        if (@($octets | Where-Object { $_ -gt 255 }).Count -gt 0) { return $null }

        [int64]$addr = ([int64]$octets[0] -shl 24) -bor ([int64]$octets[1] -shl 16) -bor
                       ([int64]$octets[2] -shl 8)  -bor  [int64]$octets[3]

        [int64]$mask = if ($bits -eq 0) { 0L } else { (0xFFFFFFFFL -shl (32 - $bits)) -band 0xFFFFFFFFL }
        [int64]$net   = $addr -band $mask
        [int64]$bcast = $net -bor (0xFFFFFFFFL -bxor $mask)

        return @($net, $bcast)
    }

    $a = ConvertTo-Range $CidrA
    $b = ConvertTo-Range $CidrB
    if (-not $a -or -not $b) { return $false }

    return ($a[0] -le $b[1] -and $b[0] -le $a[1])
}

function Test-LzExistingLandingZone {
    <#
    .SYNOPSIS
        Heuristic: does this tenant already contain a landing zone?
    .DESCRIPTION
        Used to challenge a 'greenfield' declaration. Getting this wrong in the
        permissive direction is the expensive error — a greenfield run against a
        populated tenant can collide with live infrastructure — so the signals
        here are deliberately sensitive and reported as "review this", not as a
        determination.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Probes)

    $signals = @()

    $mg = $Probes['Management groups']
    if ($mg.Status -eq 'Ok') {
        # A tenant with no landing zone typically has only the Tenant Root Group.
        if ($mg.Count -gt 1) {
            $signals += "A management group hierarchy already exists ($($mg.Count) groups). A greenfield build would add to it, not replace it."
        }
        $cafLike = @($mg.Items | Where-Object { $_.DisplayName -match '(?i)platform|landing\s*zone|connectivity|identity|sandbox|decommission' })
        if ($cafLike.Count -ge 2) {
            $signals += "Management groups matching CAF naming were found ($($cafLike.Count)). This tenant likely already has a landing zone; treat the deployment as brownfield."
        }
    }

    $pa = $Probes['Policy assignments']
    if ($pa.Status -eq 'Ok' -and $pa.Count -gt 5) {
        $signals += "$($pa.Count) policy assignments already exist. Existing Deny assignments can block the first apply."
    }

    $law = $Probes['Log Analytics workspaces']
    if ($law.Status -eq 'Ok' -and $law.Count -gt 0) {
        $signals += "$($law.Count) Log Analytics workspace(s) already exist. Confirm whether the landing zone should adopt one rather than create another."
    }

    [pscustomobject]@{
        LikelyExisting = ($signals.Count -gt 0)
        Signals        = $signals
    }
}
