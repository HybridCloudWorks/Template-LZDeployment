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
    $configRaw = Get-Content $ConfigPath -Raw
    $config = $configRaw | ConvertFrom-Json -Depth 30

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

    # ── Guard G00: schema validation ─────────────────────────────────────────
    # The JSON Schema is the configuration contract; validating it first means
    # the guard chain and token engine only ever see a structurally valid
    # document. Fails closed: no schema, or an invalid document, stops the
    # render before anything is evaluated or written.
    Write-LzRenderSection 'Schema validation (G00)'
    $schemaPath = Join-Path $factoryRoot 'factory/schema/lz-config.schema.json'
    if (-not (Test-Path $schemaPath)) {
        throw "G00: configuration schema not found: $schemaPath. Failing closed — the configuration contract cannot be verified. Nothing was written."
    }
    $schemaErrors = $null
    $schemaValid = Test-Json -Json $configRaw -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable schemaErrors
    if (-not $schemaValid) {
        $schemaDetail = (@($schemaErrors | ForEach-Object { $_.Exception.Message } | Select-Object -First 10) -join ' | ')
        throw "G00: the configuration does not validate against lz-config.schema.json. Nothing was written. Details: $schemaDetail"
    }
    Write-LzRenderOK 'Configuration validates against lz-config.schema.json.'

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
    $context = New-LzRenderContext -Config $config -Discovery $discovery -FactoryVersion $factoryVersion -SchemaPath $schemaPath
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

        $mode = if ($entry.PSObject.Properties.Name -contains 'mode') { $entry.mode } else { 'render' }

        # Two modes have no template file: config-snapshot writes the validated
        # answer record itself, version-stamp writes the generator's version
        # metadata. Both go through the manifest so the inventory-integrity
        # gate (V01) accounts for them like any other emitted file.
        $sourcePath = Join-Path $TemplateRoot $entry.source
        if ($mode -notin @('config-snapshot', 'version-stamp') -and -not (Test-Path $sourcePath)) {
            throw "Manifest references a template that does not exist: $($entry.source)"
        }

        $outPath = Join-Path $OutputDirectory $destination

        # A write that ShouldProcess declines (-WhatIf) is recorded as skipped,
        # not emitted: the manifest and the OK log must only ever describe
        # files that actually exist on disk.
        if ($PSCmdlet.ShouldProcess($destination, 'render')) {
            $dir = Split-Path -Parent $outPath
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

            if ($mode -eq 'config-snapshot') {
                # The answer record, committed into the generated repository so
                # the estate's provenance survives the factory copy's deletion.
                # The wizard collects no secret fields (CI-enforced zero-network
                # posture); the snapshot is the validated configuration as-is.
                Set-Content -Path $outPath -Value $configRaw -Encoding utf8
            }
            elseif ($mode -eq 'version-stamp') {
                $stamp = [ordered]@{
                    '$comment'     = 'Generator version stamp. Records which factory release produced this repository.'
                    factoryVersion = if ($factoryVersion) { $factoryVersion.factoryVersion } else { 'unknown' }
                    schemaVersion  = $config.schemaVersion
                    generatedAt    = $config.generatedAt
                    renderer       = 'LZFactory.Renderer'
                }
                Set-Content -Path $outPath -Value ($stamp | ConvertTo-Json -Depth 5) -Encoding utf8
            }
            elseif ($mode -eq 'copy') {
                Copy-Item -Path $sourcePath -Destination $outPath -Force
            }
            else {
                $template = Get-Content $sourcePath -Raw
                $rendered = Resolve-LzTemplate -Template $template -Context $context -SourceName $entry.source
                Set-Content -Path $outPath -Value $rendered -Encoding utf8 -NoNewline:$false
            }

            $emitted += [pscustomobject]@{
                Source      = $entry.source
                Destination = $destination
                Mode        = $mode
            }
            Write-LzRenderOK $destination
        }
        else {
            $skipped += [pscustomobject]@{ Source = $entry.source; Reason = 'write declined by ShouldProcess (WhatIf)' }
        }
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

                $emitted += [pscustomobject]@{ Source = $entry.source; Destination = $destination; Mode = 'render'; Layer = $layer }
                Write-LzRenderOK $destination
            }
            else {
                $skipped += [pscustomobject]@{ Source = "$($entry.source) [$layer]"; Reason = 'write declined by ShouldProcess (WhatIf)' }
            }
        }
    }

    # ── Directory copies ─────────────────────────────────────────────────────
    # The module corpus is several hundred static files. Listing each one in the
    # manifest would add no decision — modules are copied verbatim — while
    # creating a trap where a newly added .tf is silently not shipped. A
    # directory entry is therefore the safer unit for content that carries no
    # per-configuration variation. Everything that DOES vary stays in `files`,
    # where its condition is visible.
    if ($manifest.PSObject.Properties.Name -contains 'directories') {
        foreach ($entry in @($manifest.directories)) {
            $when = if ($entry.PSObject.Properties.Name -contains 'when') { $entry.when } else { 'always' }
            if ($when -ne 'always' -and -not (Test-LzExpression -Expression $when -Context $context)) {
                $skipped += [pscustomobject]@{ Source = "$($entry.source)/**"; Reason = "condition not met: $when" }
                continue
            }

            $sourceDir = Join-Path $TemplateRoot $entry.source
            if (-not (Test-Path $sourceDir)) {
                throw "Manifest references a directory that does not exist: $($entry.source)"
            }

            $exclude = @()
            if ($entry.PSObject.Properties.Name -contains 'exclude') { $exclude = @($entry.exclude) }

            $copied = 0
            foreach ($file in @(Get-ChildItem -Path $sourceDir -Recurse -File -Force)) {
                # Relative path with forward slashes, so exclude patterns read
                # the same on Windows and Linux.
                $relative = ($file.FullName.Substring((Resolve-Path $sourceDir).Path.Length)).TrimStart('\', '/') -replace '\\', '/'

                $skip = $false
                foreach ($pattern in $exclude) {
                    if ($relative -like $pattern) { $skip = $true; break }
                }
                if ($skip) { continue }

                $outPath = Join-Path $OutputDirectory (Join-Path $entry.destination $relative)
                if ($PSCmdlet.ShouldProcess("$($entry.destination)/$relative", 'copy')) {
                    $dir = Split-Path -Parent $outPath
                    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    Copy-Item -Path $file.FullName -Destination $outPath -Force
                    $emitted += [pscustomobject]@{
                        Source      = "$($entry.source)/$relative"
                        Destination = "$($entry.destination)/$relative"
                        Mode        = 'copy'
                    }
                    $copied++
                }
                else {
                    $skipped += [pscustomobject]@{ Source = "$($entry.source)/$relative"; Reason = 'write declined by ShouldProcess (WhatIf)' }
                }
            }
            Write-LzRenderOK "$($entry.destination)/ ($copied file(s))"
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
