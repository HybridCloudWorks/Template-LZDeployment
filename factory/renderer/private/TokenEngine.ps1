#Requires -Version 7.0
<#
    Landing Zone Factory — token engine.

    TOKEN SYNTAX AND WHY IT LOOKS LIKE THIS
    ---------------------------------------
    Templates are tokenised with {{FACTORY:...}}, never with ${...}. Terraform
    uses ${...} for its own interpolation, so a factory token sharing that
    syntax would be ambiguous inside every .tf file in the corpus and would
    break `terraform fmt` on the raw template. This is control AR4 in
    docs/factory/FACTORY-DESIGN.md.

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
        [object]$FactoryVersion = $null
    )

    $map = [ordered]@{}

    # Flatten the configuration itself.
    Add-LzFlattenedObject -Target $map -Object $Config -Prefix ''

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

    $map['computed.backendIsHcp'] = ($Config.backend.type -eq 'hcp-terraform')
    $map['computed.backendIsAzurerm'] = ($Config.backend.type -eq 'azurerm')

    if ($Config.backend.type -eq 'hcp-terraform') {
        $map['computed.workspacePrefix'] = $Config.backend.hcpTerraform.workspacePrefix
    }

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

    # Tag map rendered into every layer's default_tags.
    $map['computed.defaultTags'] = $Config.naming.defaultTags

    if ($Discovery) { $map['computed.discoveryAvailable'] = $true }
    else { $map['computed.discoveryAvailable'] = $false }

    [pscustomobject]@{
        Config = $Config
        Tokens = $map
        Keys   = @($map.Keys)
    }
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

    $layers = @('global')

    if ($Config.connectivity.model -ne 'none') { $layers += 'platform-connectivity' }
    $layers += 'platform-management'

    if ((Test-LzHasProperty $Config.azure.subscriptions 'identity') -and
        $Config.azure.subscriptions.identity) {
        $layers += 'platform-identity'
    }

    if ($Config.environments.application -contains 'prod') { $layers += 'workloads-prod' }
    if ($Config.environments.application -contains 'dev' -or
        $Config.environments.application -contains 'test' -or
        $Config.environments.application -contains 'uat') {
        $layers += 'workloads-nonprod'
    }

    # The sandbox layer needs its own subscription; emitting it without one
    # produces a layer that cannot plan.
    if ($Config.environments.application -contains 'sandbox' -and
        (Test-LzHasProperty $Config.azure.subscriptions 'sandbox') -and
        $Config.azure.subscriptions.sandbox) {
        $layers += 'sandbox'
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
