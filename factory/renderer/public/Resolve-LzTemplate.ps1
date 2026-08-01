#Requires -Version 7.0
<#
    Template resolution — turns one template's text into rendered output.

    Two passes, in this order:

      1. Directives (#{{IF}} / #{{FOREACH}}) decide which LINES survive.
      2. Tokens ({{FACTORY:...}}) substitute values into the surviving lines.

    That ordering matters: a token inside a block that the conditional removes
    must never be evaluated. Otherwise a configuration that legitimately omits,
    say, ExpressRoute settings would fail to render because a token in the
    (excluded) ExpressRoute block referenced a path that is absent.
#>

Set-StrictMode -Version Latest

# Substituted values are masked so they are inert for the remainder of the
# render. Without this, a FOREACH body's output (already token-expanded with
# the scoped context) flows into the outer token pass, where a legitimate value
# containing '{{' would be either re-expanded or rejected as a residual
# placeholder. The mask uses Unicode private-use characters that never occur in
# templates or configuration values, and is removed once — at the end of
# Resolve-LzTemplate, after the residual-token check has run.
$script:LzMaskOpen  = [string][char]0xE000
$script:LzMaskClose = [string][char]0xE001

function Protect-LzRenderedValue {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    return $Value.Replace('{{', $script:LzMaskOpen).Replace('}}', $script:LzMaskClose)
}

function Unprotect-LzRenderedText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    return $Text.Replace($script:LzMaskOpen, '{{').Replace($script:LzMaskClose, '}}')
}

function Resolve-LzTemplate {
    <#
    .SYNOPSIS
        Render a template string against a render context.
    .PARAMETER Template
        Raw template text.
    .PARAMETER Context
        Output of New-LzRenderContext.
    .PARAMETER SourceName
        Used only in error messages, so a failure names the offending file.
    .OUTPUTS
        The rendered string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Template,
        [Parameter(Mandatory)][object]$Context,
        [string]$SourceName = '<template>'
    )

    $afterDirectives = Expand-LzDirectives -Template $Template -Context $Context -SourceName $SourceName
    $rendered = Expand-LzTokens -Template $afterDirectives -Context $Context -SourceName $SourceName

    Assert-LzNoResidualTokens -Text $rendered -SourceName $SourceName

    # Substituted spans were masked by Expand-LzTokens so they could not be
    # re-expanded or misread as residual placeholders. Restore them now that
    # every expansion pass and the residual check have completed.
    return Unprotect-LzRenderedText $rendered
}

function Expand-LzDirectives {
    <#
    .SYNOPSIS
        Process #{{IF}} / #{{ELSEIF}} / #{{ELSE}} / #{{ENDIF}} and
        #{{FOREACH x IN path}} / #{{ENDFOREACH}} line directives.
    .DESCRIPTION
        Directive lines are consumed entirely — they never appear in output.
        Nesting is supported. An unbalanced directive is a hard error: silently
        tolerating one would emit a template fragment as literal content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Template,
        [Parameter(Mandatory)][object]$Context,
        [string]$SourceName = '<template>'
    )

    # An empty template (a FOREACH with no body, for instance) splits to a
    # single empty string, which cannot bind to the [string[]] parameters below.
    if ([string]::IsNullOrEmpty($Template)) { return '' }

    $lines = @($Template -split "`r?`n")
    $result = New-Object System.Collections.Generic.List[string]

    # Each frame: Kind (If|Foreach), Active (are we emitting?),
    # AnyBranchTaken (has an IF branch already matched?),
    # plus loop bookkeeping for Foreach.
    $stack = New-Object System.Collections.Generic.List[hashtable]

    $emitting = {
        if ($stack.Count -eq 0) { return $true }
        foreach ($f in $stack) { if (-not $f.Active) { return $false } }
        return $true
    }

    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        if ($line -match $script:LzDirectivePattern) {
            $directive = $Matches['directive']
            $expr = if ($Matches.ContainsKey('expr')) { $Matches['expr'] } else { '' }

            switch ($directive) {
                'IF' {
                    # Only evaluate when the enclosing scope is live; a condition
                    # inside a skipped block may reference paths that do not exist.
                    $parentLive = & $emitting
                    $value = $false
                    if ($parentLive) { $value = Test-LzExpression -Expression $expr -Context $Context }
                    $stack.Add(@{ Kind = 'If'; Active = $value; AnyBranchTaken = $value; Line = $i + 1 })
                }
                'ELSEIF' {
                    if ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Kind -ne 'If') {
                        throw "$SourceName line $($i + 1): ELSEIF without a matching IF."
                    }
                    $frame = $stack[$stack.Count - 1]
                    if ($frame.AnyBranchTaken) { $frame.Active = $false }
                    else {
                        $frame.Active = Test-LzExpression -Expression $expr -Context $Context
                        if ($frame.Active) { $frame.AnyBranchTaken = $true }
                    }
                }
                'ELSE' {
                    if ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Kind -ne 'If') {
                        throw "$SourceName line $($i + 1): ELSE without a matching IF."
                    }
                    $frame = $stack[$stack.Count - 1]
                    $frame.Active = -not $frame.AnyBranchTaken
                    if ($frame.Active) { $frame.AnyBranchTaken = $true }
                }
                'ENDIF' {
                    if ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Kind -ne 'If') {
                        throw "$SourceName line $($i + 1): ENDIF without a matching IF."
                    }
                    $stack.RemoveAt($stack.Count - 1)
                }
                'FOREACH' {
                    if ($expr -notmatch '^\s*(?<var>[A-Za-z_][A-Za-z0-9_]*)\s+IN\s+(?<path>[A-Za-z0-9_.\[\]-]+)\s*$') {
                        throw "$SourceName line $($i + 1): malformed FOREACH. Expected: FOREACH <var> IN <path>"
                    }
                    $varName = $Matches['var']
                    $path = $Matches['path']

                    $parentLive = & $emitting
                    $items = @()
                    if ($parentLive) { $items = @(Get-LzTokenValue -Context $Context -Path $path) }

                    # Capture the loop body, then render it once per item.
                    $bodyStart = $i + 1
                    $bodyEnd = Find-LzMatchingEnd -Lines $lines -StartIndex $i -Open 'FOREACH' -Close 'ENDFOREACH' -SourceName $SourceName
                    $body = if ($bodyEnd -gt $bodyStart) { $lines[$bodyStart..($bodyEnd - 1)] } else { @() }

                    if ($parentLive) {
                        foreach ($item in $items) {
                            $scoped = New-LzScopedContext -Context $Context -Name $varName -Value $item
                            $bodyText = ($body -join "`n")

                            $expanded = Expand-LzDirectives -Template $bodyText -Context $scoped -SourceName $SourceName

                            # Loop-scoped tokens must be substituted HERE, with the
                            # scoped context, not deferred to the global token pass.
                            # By the time that pass runs the loop variable is out of
                            # scope, and {{FACTORY:<var>}} would fail as an unknown path.
                            $expanded = Expand-LzTokens -Template $expanded -Context $scoped -SourceName $SourceName

                            foreach ($outLine in ($expanded -split "`r?`n")) { $result.Add($outLine) }
                        }
                    }

                    $i = $bodyEnd   # Skip to ENDFOREACH; the loop increment consumes it.
                }
                'ENDFOREACH' {
                    # Reached only via the FOREACH skip above.
                }
            }

            $i++
            continue
        }

        if (& $emitting) { $result.Add($line) }
        $i++
    }

    if ($stack.Count -gt 0) {
        $f = $stack[0]
        throw "${SourceName}: unbalanced $($f.Kind) directive opened at line $($f.Line) and never closed."
    }

    return ($result -join "`n")
}

function Find-LzMatchingEnd {
    <#
    .SYNOPSIS
        Index of the directive line closing the block opened at StartIndex.
    #>
    param(
        # AllowEmptyString is required, not cosmetic: PowerShell's Mandatory
        # validation rejects a [string[]] containing ANY empty-string element,
        # so without this every template with a blank line fails to bind here.
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory)][int]$StartIndex,
        [Parameter(Mandatory)][string]$Open,
        [Parameter(Mandatory)][string]$Close,
        [string]$SourceName = '<template>'
    )

    $depth = 0
    for ($j = $StartIndex; $j -lt $Lines.Count; $j++) {
        if ($Lines[$j] -match $script:LzDirectivePattern) {
            $d = $Matches['directive']
            if ($d -eq $Open) { $depth++ }
            elseif ($d -eq $Close) {
                $depth--
                if ($depth -eq 0) { return $j }
            }
        }
    }
    throw "$SourceName line $($StartIndex + 1): $Open has no matching $Close."
}

function New-LzScopedContext {
    <#
    .SYNOPSIS
        Clone a context with one extra loop variable bound.
    .DESCRIPTION
        The loop variable is exposed both as `<var>` (the item itself) and, when
        the item is an object, as `<var>.<property>`, so loop bodies can token
        into an item's fields.
    #>
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    $tokens = [ordered]@{}
    foreach ($k in $Context.Tokens.Keys) { $tokens[$k] = $Context.Tokens[$k] }
    $tokens[$Name] = $Value

    if (Test-LzIsComposite $Value) {
        Add-LzFlattenedObject -Target $tokens -Object $Value -Prefix $Name
    }

    [pscustomobject]@{
        Config = $Context.Config
        Tokens = $tokens
        Keys   = @($tokens.Keys)
    }
}

function Expand-LzTokens {
    <#
    .SYNOPSIS
        Substitute every {{FACTORY...}} token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Template,
        [Parameter(Mandatory)][object]$Context,
        [string]$SourceName = '<template>'
    )

    $evaluator = {
        param([System.Text.RegularExpressions.Match]$m)

        $kind = $m.Groups['kind'].Value
        $path = $m.Groups['path'].Value

        try { $value = Get-LzTokenValue -Context $Context -Path $path }
        catch { throw "$SourceName : $($_.Exception.Message)" }

        $substituted = switch ($kind) {
            ''       { ConvertTo-LzHclString $value }
            '-RAW'   { [string]$value }
            '-BOOL'  { ConvertTo-LzBoolLiteral $value }
            '-NUM'   { if ($null -eq $value) { '0' } else { [string]$value } }
            '-LIST'  { ConvertTo-LzHclList $value }
            '-MAP'   { ConvertTo-LzHclMap $value }
            '-JSON'  { ConvertTo-Json -InputObject $value -Compress -Depth 12 }
            default  { throw "$SourceName : unsupported token kind '$kind'." }
        }

        # Mask the substituted text so a later expansion pass (the global pass
        # after a FOREACH, or an enclosing loop) treats it as literal output:
        # values are data, never templates to expand again.
        return Protect-LzRenderedValue $substituted
    }

    return [regex]::Replace($Template, $script:LzTokenPattern, $evaluator)
}

function Assert-LzNoResidualTokens {
    <#
    .SYNOPSIS
        Fail if any {{...}} survived rendering.
    .DESCRIPTION
        Catches typos the main token pattern cannot match, such as
        {{FACTORY-LST:x}} or {{FACTORY x}}. Without this, a mistyped token would
        ship verbatim into customer Terraform, where it becomes a syntax error
        at best and a wrong value at worst.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$SourceName = '<template>'
    )

    $residual = [regex]::Matches($Text, $script:LzResidualPattern)
    if ($residual.Count -gt 0) {
        $samples = ($residual | Select-Object -First 3 | ForEach-Object { $_.Value }) -join ', '
        throw "$SourceName : $($residual.Count) unresolved placeholder(s) remain after rendering: $samples. Check for a mistyped token kind — valid kinds are {{FACTORY:}}, {{FACTORY-RAW:}}, {{FACTORY-BOOL:}}, {{FACTORY-NUM:}}, {{FACTORY-LIST:}}, {{FACTORY-MAP:}}, {{FACTORY-JSON:}}."
    }
}
