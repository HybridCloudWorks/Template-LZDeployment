#Requires -Version 7.0
<#
.SYNOPSIS
    Plan-verify the ALZ provider's resolution of a RENDERED estate (TODO 6.1a).
.DESCRIPTION
    Everything else in this repository stops at `terraform validate`, and
    validate does not resolve data sources. That gap is not theoretical: the
    global layer's cross-layer state read was pointed at the wrong backend for
    the entire life of the HCP option and every CI check passed, because the
    only thing that would have noticed is a plan.

    This is the first thing here that plans.

    It cannot plan the rendered layer as-is. That layer reads six of its
    fourteen policy_default_values out of `data.terraform_remote_state.management`,
    so planning it needs the platform-management layer already APPLIED in a real
    tenant — a deployment, not a check. So instead this builds a standalone
    module around the one thing worth reaching:

        data "alz_architecture"

    which is where the ALZ provider resolves policy_default_values against the
    pinned library and applies policy_assignments_to_modify per management
    group. The argument mapping mirrors Azure/avm-ptn-alz/azurerm main.tf at the
    pinned version; the values are EXTRACTED FROM THE RENDER rather than
    written here, because a harness supplied with its own inputs proves only
    that it agrees with itself.

    WHAT THIS NEEDS, AND WHY IT IS LESS THAN TODO 6.1a ASSUMED

    An Azure credential — but only a reading one. alzlib fetches built-in policy
    and policy set definitions through armpolicy.ClientFactory to check that
    every assigned definition is assignable and to compute the role assignments
    DeployIfNotExists and Modify assignments require. Reader on any subscription
    is enough. There is no throwaway tenant, no management group, no applied
    layer, and nothing is created.

    Supply `-CacheFile` (a .gz from `alzlibtool cache create`) to skip the
    built-in fetch entirely and run with no credential at all. The cache must be
    regenerated periodically or the provider will miscalculate policy role
    assignments against stale built-in versions — the provider's own warning.
.PARAMETER Fixture
    Fixture basename under factory/tests/fixtures, without .json.
.PARAMETER CacheFile
    Optional gzipped built-in policy cache. When supplied the provider reads
    built-ins from it instead of from Azure, and no credential is needed.
.PARAMETER WorkDirectory
    Where to build the harness module. Defaults to a temp directory, removed on
    exit unless -Keep is set.
.PARAMETER AssembleOnly
    Build the harness module and stop before `terraform init`. Everything up to
    that point — rendering, extraction, substitution — needs neither a
    credential nor the Terraform registry, so this is the half that CAN run on
    every pull request. It catches an extraction regression, which is the way
    this harness would otherwise rot: a truncated block or a missed
    substitution still produces a module that plans, just not the one the
    estate rendered.
.PARAMETER Keep
    Leave the generated module in place for inspection.
#>
[CmdletBinding()]
param(
    [string]$Fixture = 'azurerm-config',
    [string]$CacheFile = '',
    [string]$WorkDirectory = '',
    [switch]$AssembleOnly,
    [switch]$Keep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# The six values the rendered layer reads out of the management layer's state.
# The provider validates the SHAPE of a policy default and that the assignment
# parameter it feeds exists — not that the resource behind it does — so a
# well-formed id of the right type is a faithful stand-in. They are spelled out
# rather than pattern-matched so that a NEW remote-state read added to the layer
# fails this harness loudly instead of being silently substituted with junk.
$script:RemoteStateStandIns = [ordered]@{
    'log_analytics_workspace_id'      = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-plan-proof/providers/Microsoft.OperationalInsights/workspaces/log-alz-plan-proof'
    'ama_user_assigned_identity_id'   = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-plan-proof/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ama-plan-proof'
    'ama_user_assigned_identity_name' = 'id-ama-plan-proof'
    'dcr_vm_insights_id'              = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-plan-proof/providers/Microsoft.Insights/dataCollectionRules/dcr-vm-insights'
    'dcr_defender_sql_id'             = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-plan-proof/providers/Microsoft.Insights/dataCollectionRules/dcr-defender-sql'
    'dcr_change_tracking_id'          = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-alz-plan-proof/providers/Microsoft.Insights/dataCollectionRules/dcr-change-tracking'
}

function Get-LzBalancedBlock {
    <#
    .SYNOPSIS
        The text of an HCL block, from its opening line to its matching brace.
    .DESCRIPTION
        Brace counting rather than a regex, because policy_default_values is
        full of nested jsonencode({ ... }) and a non-greedy match stops at the
        first one. Strings and comments are skipped so a brace inside either
        cannot end the block early.
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$OpenPattern
    )

    $match = [regex]::Match($Text, $OpenPattern)
    if (-not $match.Success) { return $null }

    $start = $match.Index
    $i = $Text.IndexOf('{', $start)
    if ($i -lt 0) { return $null }

    $depth = 0
    $inString = $false
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if ($inString) {
            if ($ch -eq '\') { $i += 2; continue }
            if ($ch -eq '"') { $inString = $false }
        }
        elseif ($ch -eq '"') { $inString = $true }
        elseif ($ch -eq '#') { while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ } }
        elseif ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
        }
        $i++
    }
    throw "Unbalanced braces while extracting a block matching /$OpenPattern/."
}

function Test-LzEmittedLibrary {
    <#
    .SYNOPSIS
        Structural checks on the local ALZ library, before any plan.
    .DESCRIPTION
        These run with no credential and no network, which is what makes them
        worth having: the plan that would catch the same faults is dispatch-only
        and needs a Reader identity, so without this a PR can merge a library
        the provider cannot read and every check stays green.

        Each check exists because the failure it catches is silent or
        misattributed:

        * `archetypes` is a REQUIRED ARRAY in the library's own schema. Emitting
          a bare string is easy in PowerShell — the pipeline unrolls a
          single-element array — and it has already happened once. terraform
          validate never resolves the data source that reads this file.

        * The provider indexes a policy assignment by its `name` field and finds
          the file by basename. A mismatch is not an error anywhere: the
          assignment is simply never found, and the estate deploys without a
          control the client was told it had.

        * An override naming a base archetype nothing defines, or an
          architecture binding an archetype name nothing emits, fails at plan
          time with a message about archetypes rather than about the answer that
          produced it.
    #>
    param([Parameter(Mandatory)][string]$LibraryRoot)

    $architectures = @(Get-ChildItem (Join-Path $LibraryRoot 'architecture_definitions') -Filter '*.alz_architecture_definition.json' -ErrorAction SilentlyContinue)
    if ($architectures.Count -eq 0) { throw "A local library was emitted at $LibraryRoot with no architecture definition in it." }

    # Archetype names this library defines locally. A base_archetype naming one
    # of the PINNED library's archetypes is correct and unresolvable from here,
    # so only locally-defined names are cross-checked.
    $localArchetypes = @(Get-ChildItem (Join-Path $LibraryRoot 'archetype_definitions') -Filter '*.alz_archetype_override.yaml' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name -replace '\.alz_archetype_override\.yaml$', '' })

    foreach ($file in $architectures) {
        $raw = Get-Content $file.FullName -Raw
        if ($raw -match '"archetypes"\s*:\s*"') {
            throw "$($file.Name) emits `"archetypes`" as a string. The library schema requires an array on every management group; a single-element array unrolled somewhere in the renderer."
        }
        $architecture = $raw | ConvertFrom-Json -Depth 20
        foreach ($group in @($architecture.management_groups)) {
            if (@($group.archetypes).Count -eq 0) {
                throw "$($file.Name): management group '$($group.id)' carries no archetype, so nothing governs it."
            }
        }
    }

    foreach ($file in @(Get-ChildItem (Join-Path $LibraryRoot 'policy_assignments') -Filter '*.alz_policy_assignment.json' -ErrorAction SilentlyContinue)) {
        $assignment = Get-Content $file.FullName -Raw | ConvertFrom-Json -Depth 20
        $expected = $file.Name -replace '\.alz_policy_assignment\.json$', ''
        if ([string]$assignment.name -ne $expected) {
            throw "$($file.Name) declares name '$($assignment.name)'. The provider finds assignments by basename, so a mismatch means this assignment is never applied and nothing reports it."
        }
        if (-not $assignment.properties.policyDefinitionId) {
            throw "$($file.Name) has no policyDefinitionId."
        }
        # Every archetype that adds this assignment must be one the architecture
        # actually binds to a group, or the assignment reaches nothing.
        $carriers = @($localArchetypes | Where-Object {
                (Get-Content (Join-Path $LibraryRoot "archetype_definitions/$_.alz_archetype_override.yaml") -Raw) -match [regex]::Escape("`"$expected`"")
            })
        if ($carriers.Count -eq 0) { continue }
        $bound = $false
        foreach ($file2 in $architectures) {
            $architecture = Get-Content $file2.FullName -Raw | ConvertFrom-Json -Depth 20
            foreach ($group in @($architecture.management_groups)) {
                if (@($group.archetypes | Where-Object { $_ -in $carriers }).Count -gt 0) { $bound = $true }
            }
        }
        if (-not $bound) {
            throw "$($file.Name) is added by archetype(s) $($carriers -join ', '), but no emitted architecture definition binds any of those to a management group. The assignment would reach nothing."
        }
    }
}

function Convert-LzRemoteStateReference {
    <#
    .SYNOPSIS
        Replace management-layer state reads with literal stand-ins.
    .DESCRIPTION
        Fails on an output this harness has no stand-in for rather than leaving
        the reference in place: an unsubstituted reference would make the plan
        fail on a missing data source, and the failure would look like a defect
        in the rendered estate instead of a gap here.
    #>
    param([Parameter(Mandatory)][string]$Text)

    $unknown = @()
    foreach ($m in [regex]::Matches($Text, 'data\.terraform_remote_state\.management\.outputs\.(?<name>[A-Za-z0-9_]+)')) {
        $name = $m.Groups['name'].Value
        if (-not $script:RemoteStateStandIns.Contains($name)) { $unknown += $name }
    }
    if ($unknown.Count -gt 0) {
        throw ("The rendered global layer reads management-layer outputs this harness has no stand-in for: {0}. " -f (($unknown | Sort-Object -Unique) -join ', ')) +
              'Add each to $script:RemoteStateStandIns in factory/ci/Test-AlzArchitecturePlan.ps1 with a well-formed value of the right type.'
    }

    foreach ($name in $script:RemoteStateStandIns.Keys) {
        $Text = $Text -replace ("data\.terraform_remote_state\.management\.outputs\.$name\b"), ('"{0}"' -f $script:RemoteStateStandIns[$name])
    }
    return $Text
}

# ── Render ───────────────────────────────────────────────────────────────────
$fixturePath = Join-Path $repo "factory/tests/fixtures/$Fixture.json"
if (-not (Test-Path $fixturePath)) { throw "No such fixture: $fixturePath" }

if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path ([IO.Path]::GetTempPath()) "lz-alz-plan-$([guid]::NewGuid().ToString('n').Substring(0,8))"
}
$rendered = Join-Path $WorkDirectory 'rendered'
$harness = Join-Path $WorkDirectory 'harness'
New-Item -ItemType Directory -Force -Path $harness | Out-Null

try {
    Write-Host "Rendering fixture '$Fixture'..."
    Import-Module (Join-Path $repo 'factory/renderer/LZFactory.Renderer.psd1') -Force
    Invoke-LzRender -ConfigPath $fixturePath -OutputDirectory $rendered -Quiet | Out-Null

    $globalDir = Join-Path $rendered 'terraform/live/global'
    $mainTf = Get-Content (Join-Path $globalDir 'main.tf') -Raw

    # ── Extract, never author ────────────────────────────────────────────────
    $providerBlock = Get-LzBalancedBlock -Text $mainTf -OpenPattern '(?m)^provider\s+"alz"\s*\{'
    if (-not $providerBlock) { throw 'No provider "alz" block in the rendered global layer.' }

    $defaultsBlock = Get-LzBalancedBlock -Text $mainTf -OpenPattern '(?m)^\s*policy_default_values\s*=\s*\{'
    if (-not $defaultsBlock) { throw 'No policy_default_values in the rendered global layer.' }
    $defaultsBody = $defaultsBlock.Substring($defaultsBlock.IndexOf('{'))
    $defaultsBody = Convert-LzRemoteStateReference -Text $defaultsBody

    # The per-management-group inversion, lifted whole. Re-deriving it here
    # would test this file's copy of the rule rather than the estate's.
    $scopes = [regex]::Match($mainTf, '(?m)^\s*policy_assignment_scopes\s*=.*$').Value
    if (-not $scopes) { throw 'No policy_assignment_scopes local in the rendered global layer.' }
    $toModify = Get-LzBalancedBlock -Text $mainTf -OpenPattern '(?m)^\s*policy_assignments_to_modify\s*=\s*\{'
    if (-not $toModify) { throw 'No policy_assignments_to_modify local in the rendered global layer.' }

    $alzVersion = [regex]::Match($mainTf, '(?s)alz\s*=\s*\{.*?version\s*=\s*"(?<v>[^"]+)"').Groups['v'].Value
    if (-not $alzVersion) { throw 'Could not read the pinned alz provider version from the rendered layer.' }

    # ── Assemble ─────────────────────────────────────────────────────────────
    $cacheAttribute = if ($CacheFile) {
        $resolvedCache = (Resolve-Path $CacheFile).Path
        Copy-Item $resolvedCache (Join-Path $harness 'alzlib-cache.json.gz')
        "`n  cache_file_name = `"`${path.root}/alzlib-cache.json.gz`"`n"
    } else { '' }

    $providerWithCache = if ($cacheAttribute) {
        $providerBlock.Substring(0, $providerBlock.LastIndexOf('}')) + $cacheAttribute + '}'
    } else { $providerBlock }

    $harnessTf = @"
# GENERATED BY factory/ci/Test-AlzArchitecturePlan.ps1 — do not commit.
#
# The rendered global layer cannot be planned directly: it reads six of its
# policy_default_values out of the platform-management layer's state, so a plan
# of it needs that layer APPLIED. This module keeps the only part a plan can
# reach without a deployment — the ALZ provider's own resolution — and feeds it
# the values this estate actually rendered.
#
# The argument mapping mirrors Azure/avm-ptn-alz/azurerm main.tf. If that
# module changes which arguments it passes, this stops proving what it claims.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    alz = {
      source  = "azure/alz"
      version = "$alzVersion"
    }
  }
}

$providerWithCache

locals {
$scopes

$toModify

  policy_default_values = $defaultsBody
}

data "alz_architecture" "proof" {
  name = var.architecture_name

  # data.azurerm_client_config.current.tenant_id in the rendered layer. The
  # provider treats this as the hierarchy root's parent, and reads nothing from
  # it, so a literal keeps the plan free of an Azure data source.
  root_management_group_id = var.root_parent_management_group_id != "" ? var.root_parent_management_group_id : "00000000-0000-0000-0000-000000000000"

  location                     = var.primary_region
  policy_assignments_to_modify = local.policy_assignments_to_modify
  policy_default_values        = local.policy_default_values
}

output "management_group_count" {
  value = length(data.alz_architecture.proof.management_groups)
}

output "management_group_ids" {
  value = sort([for g in data.alz_architecture.proof.management_groups : g.id])
}
"@

    Set-Content (Join-Path $harness 'main.tf') $harnessTf -Encoding utf8

    # The estate's own variable declarations and values, unedited. Terraform
    # ignores declared variables nothing reads, so the whole file travels.
    Copy-Item (Join-Path $globalDir 'variables.tf') $harness
    Copy-Item (Join-Path $globalDir 'terraform.auto.tfvars') $harness

    # A client-named hierarchy points library_references at ${path.root}/lib.
    $libDir = Join-Path $globalDir 'lib'
    if (Test-Path $libDir) {
        Copy-Item $libDir $harness -Recurse
        Test-LzEmittedLibrary -LibraryRoot (Join-Path $harness 'lib')
    }

    # ── Plan ─────────────────────────────────────────────────────────────────
    Write-Host "Harness module: $harness"

    if ($AssembleOnly) {
        # Assert here rather than leaving it to the plan: an unsubstituted
        # remote-state reference fails at plan time with a missing-data-source
        # error that reads like a defect in the estate rather than a gap here.
        $assembled = Get-Content (Join-Path $harness 'main.tf') -Raw
        if ($assembled -match 'terraform_remote_state') {
            throw 'The assembled harness still references terraform_remote_state. Substitution is incomplete.'
        }
        if ($assembled -match 'data\s+"azurerm_client_config"') {
            throw 'The assembled harness still declares an azurerm data source, which would need a credential the harness does not use.'
        }
        Write-Host "Assembled only (-AssembleOnly): no terraform init, no plan, no credential required."
        return
    }

    if (-not $CacheFile) {
        Write-Host 'No -CacheFile supplied: the provider will fetch built-in policy definitions from Azure, which needs a credential with read access.'
    }

    & terraform "-chdir=$harness" init -input=false -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed in the harness module (exit $LASTEXITCODE)." }

    & terraform "-chdir=$harness" plan -input=false -no-color -lock=false
    if ($LASTEXITCODE -ne 0) {
        throw "terraform plan failed for fixture '$Fixture' (exit $LASTEXITCODE). This is the ALZ provider rejecting what the renderer emitted — a policy default that does not match its assignment's parameter, an assignment named in policy_assignments_to_modify that the pinned library does not carry, or an architecture definition the provider will not load."
    }

    Write-Host "ALZ architecture plan proof passed for fixture '$Fixture'."
}
finally {
    if (-not $Keep) { Remove-Item -Recurse -Force $WorkDirectory -ErrorAction SilentlyContinue }
    else { Write-Host "Kept: $WorkDirectory" }
}
