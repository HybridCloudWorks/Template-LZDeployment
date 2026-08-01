#Requires -Version 7.0
<#
    Landing Zone Factory — Discovery Engine, shared internals.

    THE CENTRAL RULE OF THIS FILE
    ----------------------------
    A probe must never conflate "there is nothing here" with "I was not allowed
    to look". Those two results lead to opposite decisions: the first says a
    greenfield build is safe, the second says the operator lacks the access the
    deployment will need. Reporting a forbidden probe as an empty inventory is
    how a factory silently builds on top of resources it could not see.

    Every probe therefore returns one of five discrete states, and `Empty` and
    `Forbidden` are distinct values that never collapse into each other. This
    implements control BR2 from the Factory-Design wiki page (https://github.com/saulpatinojr/HCW-Plan_LZDeployment/wiki/Factory-Design).

    READ-ONLY GUARANTEE
    -------------------
    Every command issued from the discovery engine is a GET/list operation.
    Nothing here creates, updates, or deletes. Invoke-LzProbe asserts this for
    Azure CLI invocations by rejecting known-mutating verbs before execution,
    so a future edit cannot quietly introduce a write.
#>

Set-StrictMode -Version Latest

# ══════════════════════════════════════════════════════════════════════════════
#  Probe result contract
# ══════════════════════════════════════════════════════════════════════════════

enum LzProbeStatus {
    Ok           # Ran successfully and returned one or more items.
    Empty        # Ran successfully and the resource genuinely does not exist.
    Forbidden    # Access denied. NOT the same as Empty. Blocks readiness.
    Unavailable  # Prerequisite missing (CLI absent, not signed in, no network).
    Error        # Unexpected failure. Treated as unknown, never as Empty.
}

function New-LzProbeResult {
    <#
    .SYNOPSIS
        Construct the single result shape every probe returns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][LzProbeStatus]$Status,
        [object[]]$Items = @(),
        [string]$Message = '',
        [string]$Remediation = '',
        [int]$DurationMs = 0
    )

    [pscustomobject]@{
        Name        = $Name
        Status      = $Status.ToString()
        Count       = @($Items).Count
        Items       = @($Items)
        Message     = $Message
        Remediation = $Remediation
        DurationMs  = $DurationMs
        # Anything that is not Ok or Empty means the inventory is not trustworthy.
        Conclusive  = ($Status -eq [LzProbeStatus]::Ok -or $Status -eq [LzProbeStatus]::Empty)
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Output helpers (match the house style of scripts/Start-LandingZoneBootstrap.ps1)
# ══════════════════════════════════════════════════════════════════════════════

$script:LzQuiet = $false

function Write-LzHeader {
    param([string]$Title, [string]$Subtitle = '')
    if ($script:LzQuiet) { return }
    Write-Host ''
    Write-Host ('╔' + ('═' * 78) + '╗') -ForegroundColor Cyan
    Write-Host ('║  ' + $Title.PadRight(76) + '║') -ForegroundColor Cyan
    if ($Subtitle) { Write-Host ('║  ' + $Subtitle.PadRight(76) + '║') -ForegroundColor Gray }
    Write-Host ('╚' + ('═' * 78) + '╝') -ForegroundColor Cyan
    Write-Host ''
}

function Write-LzSection {
    param([string]$Title)
    if ($script:LzQuiet) { return }
    Write-Host ''
    Write-Host ('━' * 78) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('━' * 78) -ForegroundColor DarkCyan
}

function Write-LzStep { param([string]$Message) if (-not $script:LzQuiet) { Write-Host "  ⤳  $Message" -ForegroundColor White } }
function Write-LzOK   { param([string]$Message) if (-not $script:LzQuiet) { Write-Host "  ✓  $Message" -ForegroundColor Green } }
function Write-LzWarn { param([string]$Message) if (-not $script:LzQuiet) { Write-Host "  ⚠  $Message" -ForegroundColor Yellow } }
function Write-LzFail { param([string]$Message) if (-not $script:LzQuiet) { Write-Host "  ✗  $Message" -ForegroundColor Red } }
function Write-LzInfo { param([string]$Message) if (-not $script:LzQuiet) { Write-Host "     $Message" -ForegroundColor Gray } }

function Get-LzTerseMessage {
    <#
    .SYNOPSIS
        Reduce a multi-line CLI error to one readable console line.
    .DESCRIPTION
        Azure CLI errors routinely span a dozen lines with remediation blocks
        appended. Printing them in full buries the probe results the operator is
        actually scanning for. The complete message is preserved verbatim in the
        report and the JSON inventory; only the console view is condensed.
    #>
    param([AllowEmptyString()][string]$Message, [int]$MaxLength = 140)
    if ([string]::IsNullOrWhiteSpace($Message)) { return '' }

    $lines = $Message -split "`r?`n"
    $first = @($lines | Where-Object { $_.Trim() }) | Select-Object -First 1
    if (-not $first) { return '' }
    $first = $first.Trim()
    $first = Protect-LzSecretText $first
    if ($first.Length -gt $MaxLength) { $first = $first.Substring(0, $MaxLength - 3) + '...' }
    return $first
}

function Write-LzProbeResult {
    param([Parameter(Mandatory)][object]$Result)
    switch ($Result.Status) {
        'Ok'          { Write-LzOK   ("{0}: {1} found" -f $Result.Name, $Result.Count) }
        'Empty'       { Write-LzInfo ("{0}: none present" -f $Result.Name) }
        'Forbidden'   { Write-LzFail ("{0}: ACCESS DENIED — inventory is incomplete, not empty" -f $Result.Name) }
        'Unavailable' { Write-LzWarn ("{0}: could not run — {1}" -f $Result.Name, (Get-LzTerseMessage $Result.Message)) }
        'Error'       { Write-LzFail ("{0}: error — {1}" -f $Result.Name, (Get-LzTerseMessage $Result.Message)) }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Command execution
# ══════════════════════════════════════════════════════════════════════════════

# Verbs that mutate. Present so a future edit cannot turn a read-only probe into
# a write without tripping this guard.
$script:LzForbiddenVerbs = @(
    'create', 'delete', 'update', 'set', 'add', 'remove', 'purge', 'restore',
    'start', 'stop', 'restart', 'deploy', 'assign', 'invoke', 'move', 'import', 'apply'
)

function Assert-LzReadOnly {
    <#
    .SYNOPSIS
        Reject any argument vector containing a mutating verb.
    .DESCRIPTION
        Discovery is read-only by contract. This is a structural guard, not a
        stylistic one: a discovery run must be safe to execute against a
        production tenant by someone who has not read the source.
    #>
    param([Parameter(Mandatory)][string[]]$Arguments)

    foreach ($arg in $Arguments) {
        # Only bare verbs count. Values like "--query" or a resource named
        # "create-thing" are not commands, so we match whole tokens only.
        if ($arg -in $script:LzForbiddenVerbs) {
            throw "Discovery engine refused a mutating command: '$arg' appears in [$($Arguments -join ' ')]. Discovery is read-only by contract."
        }
    }
}

function Invoke-LzProbe {
    <#
    .SYNOPSIS
        Run a probe scriptblock, classify its outcome, and time it.
    .DESCRIPTION
        The scriptblock is expected to return a collection. Classification:
          - throws with a permissions signature  -> Forbidden
          - throws with a "not logged in"        -> Unavailable
          - returns nothing                      -> Empty
          - returns items                        -> Ok
          - any other throw                      -> Error

        The distinction between Forbidden and Empty is the entire point; see the
        file header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Probe,
        [string]$ForbiddenRemediation = ''
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $items = & $Probe
        $sw.Stop()

        $arr = @($items | Where-Object { $null -ne $_ })
        if ($arr.Count -eq 0) {
            return New-LzProbeResult -Name $Name -Status Empty -DurationMs $sw.ElapsedMilliseconds `
                -Message 'Queried successfully; no matching resources exist.'
        }
        return New-LzProbeResult -Name $Name -Status Ok -Items $arr -DurationMs $sw.ElapsedMilliseconds
    }
    catch {
        $sw.Stop()
        $msg = $_.Exception.Message

        if (Test-LzForbiddenError $msg) {
            return New-LzProbeResult -Name $Name -Status Forbidden -DurationMs $sw.ElapsedMilliseconds `
                -Message $msg -Remediation $ForbiddenRemediation
        }
        if (Test-LzUnavailableError $msg) {
            return New-LzProbeResult -Name $Name -Status Unavailable -DurationMs $sw.ElapsedMilliseconds `
                -Message $msg -Remediation 'Sign in to the relevant CLI and re-run discovery.'
        }
        return New-LzProbeResult -Name $Name -Status Error -DurationMs $sw.ElapsedMilliseconds -Message $msg
    }
}

function Test-LzForbiddenError {
    <#
    .SYNOPSIS
        True when an error means "you are not allowed", as opposed to "it is not there".
    .DESCRIPTION
        The patterns here were widened after a live run: the GitHub CLI reports
        `(HTTP 403)`, not `(403)`, and was being classified as Error rather than
        Forbidden. That misclassification defeats the entire point of the
        Empty/Forbidden split, so this function is deliberately generous — a
        false Forbidden costs an unnecessary remediation note, while a missed
        one lets an inaccessible scope masquerade as an empty one.
    #>
    param([string]$Message)
    $patterns = @(
        'AuthorizationFailed', 'does not have authorization', 'Forbidden',
        '\(403\)', 'HTTP 403', '"status":\s*"403"', 'status.*\b403\b',
        'Insufficient privileges', 'Authorization_RequestDenied', 'AccessDenied',
        'does not have permission', 'not authorized to perform',
        'must be an org admin', 'needs the .*scope', 'fine-grained permission',
        'RBACAccessDenied', 'does not have the required'
    )
    foreach ($p in $patterns) { if ($Message -match $p) { return $true } }
    return $false
}

function Test-LzUnavailableError {
    <#
    .SYNOPSIS
        True when an error means "the tool could not run", not "access denied".
    .DESCRIPTION
        Expired or revoked tokens land here rather than in Forbidden: the
        operator's permissions are unknown, not absent, and the remediation is to
        re-authenticate rather than to request a role. AADSTS50173 (grant expired
        or revoked) was the case that surfaced this during a live run.
    #>
    param([string]$Message)
    $patterns = @(
        'Please run .az login', 'not logged in', 'no such host', 'could not be resolved',
        'is not recognized as', 'command not found', 'gh auth login',
        'Interactive authentication is needed', 'network is unreachable',
        # Token lifecycle: expired, revoked, MFA required, password changed.
        'AADSTS50058', 'AADSTS50173', 'AADSTS700082', 'AADSTS50076', 'AADSTS50079',
        'invalid_grant', 'Status_InteractionRequired', 'fresh auth token is needed',
        'az login --tenant', 'refresh token has expired',
        # Azure CLI extension not present.
        "extension.*is not installed", "'graph' is misspelled", 'No module named'
    )
    foreach ($p in $patterns) { if ($Message -match $p) { return $true } }
    return $false
}

function Invoke-LzAz {
    <#
    .SYNOPSIS
        Run an Azure CLI command read-only and return parsed JSON.
    .DESCRIPTION
        Throws on non-zero exit with stderr as the message, so Invoke-LzProbe can
        classify it. `az` writes warnings to stderr even on success, so exit code
        is the authority, not stderr content.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments)

    Assert-LzReadOnly -Arguments $Arguments

    $stdout = & az @Arguments 2>&1
    $exit = $LASTEXITCODE

    $text = ($stdout | Out-String)
    if ($exit -ne 0) { throw $text.Trim() }

    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    try { return ($text | ConvertFrom-Json -Depth 25) }
    catch { return @() }   # e.g. -o tsv output; callers that need raw use Invoke-LzAzRaw
}

function Invoke-LzAzRaw {
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments)
    Assert-LzReadOnly -Arguments $Arguments
    $stdout = & az @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($stdout | Out-String).Trim()
    if ($exit -ne 0) { throw $text }
    return $text
}

function Invoke-LzGh {
    <#
    .SYNOPSIS
        Run a GitHub CLI command read-only and return parsed JSON.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments)

    Assert-LzReadOnly -Arguments $Arguments

    $stdout = & gh @Arguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($stdout | Out-String)

    if ($exit -ne 0) { throw $text.Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    try { return ($text | ConvertFrom-Json -Depth 25) } catch { return @() }
}

$script:LzGraphTokenCache = $null

function Invoke-LzGraphApi {
    <#
    .SYNOPSIS
        Read-only GET against Microsoft Graph, bypassing the Azure CLI shim.
    .DESCRIPTION
        `az rest --url "...?$select=x&$top=200"` cannot be used reliably on
        Windows: PowerShell does not quote an argument merely because it contains
        `&`, and the az.cmd shim then hands it to cmd, which treats `&` as a
        command separator and tries to execute the query-string fragment. That
        surfaced live as: '$top' is not recognized as an internal or external
        command.

        Acquiring a token once and calling Graph through Invoke-RestMethod
        removes that entire class of quoting bug, works identically on every
        platform, and is faster than re-invoking the CLI for each request.

        The token is held in memory only and is never written to any artifact.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url)

    if (-not $script:LzGraphTokenCache) {
        # get-access-token is a read operation despite the verb reading like a
        # mutation, so it is invoked directly rather than through Assert-LzReadOnly.
        $raw = & az account get-access-token --resource-type ms-graph --output json 2>&1
        $exit = $LASTEXITCODE
        $text = ($raw | Out-String)
        if ($exit -ne 0) { throw $text.Trim() }
        try { $script:LzGraphTokenCache = ($text | ConvertFrom-Json -Depth 10).accessToken }
        catch { throw "Could not parse a Microsoft Graph access token: $($text.Trim())" }
    }

    try {
        return Invoke-RestMethod -Method Get -Uri $Url -Headers @{
            Authorization = "Bearer $script:LzGraphTokenCache"
        } -ErrorAction Stop
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($status -eq 401) { throw "Unauthorized (401) calling Microsoft Graph. The token may have expired; re-run az login." }
        if ($status -eq 403) { throw "Forbidden (403) calling Microsoft Graph: insufficient privileges for this directory object." }
        if ($status -eq 404) { return $null }
        throw $_.Exception.Message
    }
}

function ConvertTo-LzODataStartsWith {
    <#
    .SYNOPSIS
        Build a percent-encoded OData startswith() filter.
    .DESCRIPTION
        Parentheses and single quotes are encoded so the filter can travel inside
        a URL passed as an `az rest --url` argument. Passing them literally on the
        command line breaks on Windows, where the az.cmd shim hands unbalanced
        parentheses to cmd — see the note in Get-LzEntraInventory.
    #>
    param(
        [Parameter(Mandatory)][string]$Property,
        [Parameter(Mandatory)][string]$Value
    )
    # Single quotes are escaped by doubling them in OData, then percent-encoded.
    $safe = $Value -replace "'", "''"
    return "startswith%28$Property,%27$([uri]::EscapeDataString($safe))%27%29"
}

function Test-LzAzExtension {
    <#
    .SYNOPSIS
        Is a given Azure CLI extension installed?
    .DESCRIPTION
        Used to give an actionable remediation instead of a raw dynamic-install
        warning when, for example, resource-graph is absent.
    #>
    param([Parameter(Mandatory)][string]$Name)
    try {
        $exts = Invoke-LzAz extension list
        return @($exts | Where-Object { $_.name -eq $Name }).Count -gt 0
    }
    catch { return $false }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Effective-permission testing (read-only capability probing)
# ══════════════════════════════════════════════════════════════════════════════

$script:LzPermissionCache = @{}

function Get-LzEffectivePermissions {
    <#
    .SYNOPSIS
        Read the signed-in principal's effective Azure permissions at a scope.
    .DESCRIPTION
        Uses the Microsoft.Authorization/permissions API, which returns the
        actions and notActions the caller holds at the given scope. This is how
        we answer "can this operator create a management group?" WITHOUT
        creating one — capability is proven by reading the permission set, never
        by attempting the mutation and rolling it back.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Scope)

    if ($script:LzPermissionCache.ContainsKey($Scope)) { return $script:LzPermissionCache[$Scope] }

    $url = "https://management.azure.com$Scope/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
    $response = Invoke-LzAz rest --method get --url $url

    $perms = @()
    if ($response -and $response.PSObject.Properties.Name -contains 'value') { $perms = @($response.value) }

    $script:LzPermissionCache[$Scope] = $perms
    return $perms
}

function Test-LzActionPermitted {
    <#
    .SYNOPSIS
        Determine whether a specific ARM action is permitted at a scope.
    .DESCRIPTION
        Applies RBAC evaluation semantics: an action is permitted when it matches
        at least one `actions` wildcard and no `notActions` wildcard.
    .OUTPUTS
        $true / $false. Throws if the permission set cannot be read, so the
        caller can classify that as Forbidden rather than assuming "no".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Action
    )

    $perms = Get-LzEffectivePermissions -Scope $Scope
    if (-not $perms -or @($perms).Count -eq 0) { return $false }

    foreach ($p in $perms) {
        $actions = @()
        $notActions = @()
        if ($p.PSObject.Properties.Name -contains 'actions')    { $actions    = @($p.actions) }
        if ($p.PSObject.Properties.Name -contains 'notActions') { $notActions = @($p.notActions) }

        $granted = $false
        foreach ($a in $actions)    { if (Test-LzWildcardMatch -Pattern $a -Value $Action) { $granted = $true; break } }
        if (-not $granted) { continue }

        $denied = $false
        foreach ($n in $notActions) { if (Test-LzWildcardMatch -Pattern $n -Value $Action) { $denied = $true; break } }

        if (-not $denied) { return $true }
    }
    return $false
}

function Test-LzWildcardMatch {
    <#
    .SYNOPSIS
        Match an ARM action against an RBAC wildcard pattern such as
        "Microsoft.Network/*" or "*".
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Pattern,
        [Parameter(Mandatory)][string]$Value
    )
    if ([string]::IsNullOrEmpty($Pattern)) { return $false }
    if ($Pattern -eq '*') { return $true }

    $regex = '^' + ([regex]::Escape($Pattern) -replace '\\\*', '.*') + '$'
    return [bool]($Value -match $regex)
}

# ══════════════════════════════════════════════════════════════════════════════
#  Redaction
# ══════════════════════════════════════════════════════════════════════════════

function Protect-LzSecretText {
    <#
    .SYNOPSIS
        Strip anything that looks like a credential from text bound for a report.
    .DESCRIPTION
        Discovery output is written to disk and frequently pasted into tickets and
        chat. Error messages from az/gh occasionally echo tokens. Nothing here
        should ever need a secret, so we redact defensively on the way out rather
        than trusting every upstream tool not to leak.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $patterns = @(
        @{ Pattern = 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*'; Replace = '<redacted-jwt>' }
        @{ Pattern = 'gh[pousr]_[A-Za-z0-9]{16,}';                                Replace = '<redacted-github-token>' }
        @{ Pattern = '(?i)(client[_-]?secret|password|api[_-]?key|access[_-]?token)["'':=\s]+[^\s"'',;]{8,}'; Replace = '$1=<redacted>' }
        @{ Pattern = '[A-Za-z0-9_-]{20,}\.atlasv1\.[A-Za-z0-9_-]+';               Replace = '<redacted-tfc-token>' }
    )

    $out = $Text
    foreach ($p in $patterns) { $out = [regex]::Replace($out, $p.Pattern, $p.Replace) }
    return $out
}

function ConvertTo-LzSafeString {
    <#
    .SYNOPSIS
        Make a value safe to place inside a Markdown table cell.
    #>
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    $s = Protect-LzSecretText $s
    # Pipes break table layout; newlines break the row entirely.
    $s = $s -replace '\|', '\|'
    $s = $s -replace '\r?\n', ' '
    if ($s.Length -gt 300) { $s = $s.Substring(0, 297) + '...' }
    return $s
}
