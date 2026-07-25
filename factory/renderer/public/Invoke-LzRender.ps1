#Requires -Version 7.0
<#
    Render orchestrator.

    Reads the template manifest, evaluates each entry's inclusion condition,
    renders or copies the file, and writes a manifest of what it produced.

    Output is written to a staging directory, never directly into a git working
    tree, and never in place. The scaffold builder (stage 10) is what moves a
    rendered tree into a repository — keeping those separate means a failed
    render leaves nothing half-written where a push could pick it up.
#>

Set-StrictMode -Version Latest

function Invoke-LzRender {
    <#
    .SYNOPSIS
        Render the template corpus for one configuration.
    .PARAMETER ConfigPath
        Path to lz-config.json.
    .PARAMETER TemplateRoot
        Root of factory/templates.
    .PARAMETER ManifestPath
        Template manifest describing what to emit and when.
    .PARAMETER OutputDirectory
        Destination for the rendered tree.
    .PARAMETER DiscoveryPath
        Optional discovery-inventory.json, used for brownfield-aware rendering.
    .PARAMETER WhatIf
        Evaluate and report without writing anything.
    .PARAMETER Force
        Permit writing into a non-empty output directory.
    .EXAMPLE
        Invoke-LzRender -ConfigPath ./generated-output/contoso/lz-config.json `
                        -OutputDirectory ./generated-output/contoso/repo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [string]$TemplateRoot = '',
        [string]$ManifestPath = '',
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$DiscoveryPath = '',
        [switch]$Force,
        [switch]$SkipFormat,
        [switch]$Quiet
    )

    $script:LzRenderQuiet = [bool]$Quiet
    $started = Get-Date
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-LzRenderHeader 'Landing Zone Factory — Renderer (Stage 5)'

    # ── Inputs ───────────────────────────────────────────────────────────────
    if (-not (Test-Path $ConfigPath)) { throw "Configuration not found: $ConfigPath" }
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 30

    $factoryRoot = Resolve-Path (Join-Path $PSScriptRoot '../../..')
    if (-not $TemplateRoot) { $TemplateRoot = Join-Path $factoryRoot 'factory/templates' }
    if (-not $ManifestPath) { $ManifestPath = Join-Path $factoryRoot 'factory/renderer/template-manifest.json' }

    $factoryVersion = $null
    $fvPath = Join-Path $factoryRoot 'factory-version.json'
    if (Test-Path $fvPath) { $factoryVersion = Get-Content $fvPath -Raw | ConvertFrom-Json -Depth 15 }

    $discovery = $null
    if ($DiscoveryPath -and (Test-Path $DiscoveryPath)) {
        $discovery = Get-Content $DiscoveryPath -Raw | ConvertFrom-Json -Depth 25
    }

    Write-LzRenderInfo "Configuration : $($config.organization.companyName) (schema $($config.schemaVersion))"
    Write-LzRenderInfo "Templates     : $TemplateRoot"
    Write-LzRenderInfo "Output        : $OutputDirectory"

    # ── Guards ───────────────────────────────────────────────────────────────
    Write-LzRenderSection 'Render guards'
    $guards = Test-LzRenderGuards -Config $config -FactoryVersion $factoryVersion

    foreach ($g in $guards.Violations) {
        if ($g.Severity -eq 'Block') { Write-LzRenderFail "$($g.Id): $($g.Message)" }
        else { Write-LzRenderWarn "$($g.Id): $($g.Message)" }
        if ($g.Remediation) { Write-LzRenderInfo "     → $($g.Remediation)" }
    }

    if (-not $guards.CanRender) {
        throw "Render refused: $($guards.BlockCount) blocking guard violation(s). Nothing was written."
    }
    if ($guards.Violations.Count -eq 0) { Write-LzRenderOK 'All guards passed.' }

    # ── Context ──────────────────────────────────────────────────────────────
    $context = New-LzRenderContext -Config $config -Discovery $discovery
    Write-LzRenderOK "Render context built: $($context.Keys.Count) resolvable paths."
    Write-LzRenderInfo "Layers: $(($context.Tokens['computed.layers']) -join ', ')"

    # ── Manifest ─────────────────────────────────────────────────────────────
    if (-not (Test-Path $ManifestPath)) { throw "Template manifest not found: $ManifestPath" }
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -Depth 20

    # ── Output directory safety ──────────────────────────────────────────────
    if (Test-Path $OutputDirectory) {
        $existing = @(Get-ChildItem -Path $OutputDirectory -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0 -and -not $Force) {
            throw "Output directory is not empty: $OutputDirectory. Re-run with -Force to overwrite. Refusing by default so a render cannot silently destroy local edits."
        }
    }

    # ── Render ───────────────────────────────────────────────────────────────
    Write-LzRenderSection 'Rendering'
    $emitted = @()
    $skipped = @()

    foreach ($entry in $manifest.files) {
        $when = if ($entry.PSObject.Properties.Name -contains 'when') { $entry.when } else { 'always' }

        $include = $true
        if ($when -ne 'always') {
            try { $include = Test-LzExpression -Expression $when -Context $context }
            catch { throw "Manifest entry '$($entry.source)': condition '$when' failed to evaluate. $($_.Exception.Message)" }
        }

        if (-not $include) {
            $skipped += [pscustomobject]@{ Source = $entry.source; Reason = "condition not met: $when" }
            continue
        }

        # A destination path may itself contain tokens, e.g. one file per layer.
        $destination = Resolve-LzTemplate -Template $entry.destination -Context $context -SourceName "manifest:$($entry.source)"
        $destination = $destination -replace '^"|"$', ''   # destinations are unquoted

        $sourcePath = Join-Path $TemplateRoot $entry.source
        if (-not (Test-Path $sourcePath)) {
            throw "Manifest references a template that does not exist: $($entry.source)"
        }

        $mode = if ($entry.PSObject.Properties.Name -contains 'mode') { $entry.mode } else { 'render' }
        $outPath = Join-Path $OutputDirectory $destination

        if ($PSCmdlet.ShouldProcess($destination, 'render')) {
            $dir = Split-Path -Parent $outPath
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            if ($mode -eq 'copy') {
                Copy-Item -Path $sourcePath -Destination $outPath -Force
            }
            else {
                $template = Get-Content $sourcePath -Raw
                $rendered = Resolve-LzTemplate -Template $template -Context $context -SourceName $entry.source
                Set-Content -Path $outPath -Value $rendered -Encoding utf8 -NoNewline:$false
            }
        }

        $emitted += [pscustomobject]@{
            Source      = $entry.source
            Destination = $destination
            Mode        = $mode
        }
        Write-LzRenderOK $destination
    }

    # ── Per-layer expansion ──────────────────────────────────────────────────
    # Manifest entries flagged perLayer are rendered once for each active layer,
    # with `layer` bound in the context.
    foreach ($entry in @($manifest.perLayerFiles)) {
        foreach ($layer in @($context.Tokens['computed.layers'])) {
            $scoped = New-LzScopedContext -Context $context -Name 'layer' -Value $layer

            $when = if ($entry.PSObject.Properties.Name -contains 'when') { $entry.when } else { 'always' }
            if ($when -ne 'always' -and -not (Test-LzExpression -Expression $when -Context $scoped)) {
                $skipped += [pscustomobject]@{ Source = "$($entry.source) [$layer]"; Reason = "condition not met: $when" }
                continue
            }

            $destination = (Resolve-LzTemplate -Template $entry.destination -Context $scoped -SourceName "manifest:$($entry.source)") -replace '^"|"$', ''
            $sourcePath = Join-Path $TemplateRoot $entry.source
            if (-not (Test-Path $sourcePath)) { throw "Manifest references a template that does not exist: $($entry.source)" }

            $outPath = Join-Path $OutputDirectory $destination
            if ($PSCmdlet.ShouldProcess($destination, 'render')) {
                $dir = Split-Path -Parent $outPath
                if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $template = Get-Content $sourcePath -Raw
                $rendered = Resolve-LzTemplate -Template $template -Context $scoped -SourceName "$($entry.source) [$layer]"
                Set-Content -Path $outPath -Value $rendered -Encoding utf8
            }

            $emitted += [pscustomobject]@{ Source = $entry.source; Destination = $destination; Mode = 'render'; Layer = $layer }
            Write-LzRenderOK $destination
        }
    }

    # ── Normalise formatting ─────────────────────────────────────────────────
    # HCL alignment cannot be correct at template time: conditionals change
    # which lines exist, and `terraform fmt` aligns `=` across the block that
    # actually survives. Formatting the rendered output is the only place the
    # final line set is known. Without this, every generated repository fails
    # its own `terraform fmt -check` on the first pull request.
    if (-not $SkipFormat -and $PSCmdlet.ShouldProcess($OutputDirectory, 'terraform fmt')) {
        Write-LzRenderSection 'Formatting'
        $tf = Get-Command terraform -ErrorAction SilentlyContinue
        if (-not $tf) {
            Write-LzRenderWarn 'terraform not found on PATH; rendered HCL was not formatted. The generated repository may fail its own fmt check.'
        }
        else {
            $fmtOutput = & terraform fmt -recursive $OutputDirectory 2>&1
            $fmtExit = $LASTEXITCODE
            if ($fmtExit -ne 0) {
                Write-LzRenderWarn "terraform fmt exited $fmtExit. Rendered HCL may be malformed:"
                Write-LzRenderInfo (($fmtOutput | Out-String).Trim())
            }
            else {
                $changed = @($fmtOutput | Where-Object { $_ -and "$_".Trim() })
                Write-LzRenderOK "Formatted $($changed.Count) file(s)."
            }
        }
    }

    $sw.Stop()

    # ── Inventory ────────────────────────────────────────────────────────────
    $result = [pscustomobject]@{
        GeneratedAt     = $started.ToUniversalTime().ToString('o')
        FactoryVersion  = if ($factoryVersion) { $factoryVersion.factoryVersion } else { 'unknown' }
        SchemaVersion   = $config.schemaVersion
        Company         = $config.organization.companyName
        OutputDirectory = $OutputDirectory
        Layers          = @($context.Tokens['computed.layers'])
        Emitted         = $emitted
        Skipped         = $skipped
        Guards          = $guards
        DurationSeconds = $sw.Elapsed.TotalSeconds
    }

    if ($PSCmdlet.ShouldProcess('render-manifest.json', 'write')) {
        $inventoryPath = Join-Path $OutputDirectory 'render-manifest.json'
        $payload = [ordered]@{
            generatedAt    = $result.GeneratedAt
            factoryVersion = $result.FactoryVersion
            schemaVersion  = $result.SchemaVersion
            company        = $result.Company
            layers         = $result.Layers
            fileCount      = $emitted.Count
            files          = $emitted
            skipped        = $skipped
            guardWarnings  = @($guards.Violations | Where-Object { $_.Severity -eq 'Warn' })
        }
        $dir = Split-Path -Parent $inventoryPath
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $inventoryPath -Value ($payload | ConvertTo-Json -Depth 10) -Encoding utf8
    }

    Write-LzRenderSection 'Render complete'
    Write-LzRenderOK "$($emitted.Count) file(s) emitted, $($skipped.Count) skipped, in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s"
    if ($guards.WarnCount -gt 0) { Write-LzRenderWarn "$($guards.WarnCount) advisory guard warning(s) — see render-manifest.json" }

    return $result
}

# ══════════════════════════════════════════════════════════════════════════════
#  Output helpers
# ══════════════════════════════════════════════════════════════════════════════

$script:LzRenderQuiet = $false

function Write-LzRenderHeader {
    param([string]$Title)
    if ($script:LzRenderQuiet) { return }
    Write-Host ''
    Write-Host ('╔' + ('═' * 78) + '╗') -ForegroundColor Cyan
    Write-Host ('║  ' + $Title.PadRight(76) + '║') -ForegroundColor Cyan
    Write-Host ('╚' + ('═' * 78) + '╝') -ForegroundColor Cyan
    Write-Host ''
}
function Write-LzRenderSection {
    param([string]$Title)
    if ($script:LzRenderQuiet) { return }
    Write-Host ''
    Write-Host ('━' * 78) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('━' * 78) -ForegroundColor DarkCyan
}
function Write-LzRenderOK   { param([string]$m) if (-not $script:LzRenderQuiet) { Write-Host "  ✓  $m" -ForegroundColor Green } }
function Write-LzRenderWarn { param([string]$m) if (-not $script:LzRenderQuiet) { Write-Host "  ⚠  $m" -ForegroundColor Yellow } }
function Write-LzRenderFail { param([string]$m) if (-not $script:LzRenderQuiet) { Write-Host "  ✗  $m" -ForegroundColor Red } }
function Write-LzRenderInfo { param([string]$m) if (-not $script:LzRenderQuiet) { Write-Host "     $m" -ForegroundColor Gray } }
