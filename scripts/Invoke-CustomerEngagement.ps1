#Requires -Version 7.0
<#
.SYNOPSIS
    Single wrapper for one customer engagement: discovery -> broker -> render -> scaffold.

.DESCRIPTION
    Sequences the four factory stages with per-phase gates, calling each stage's
    real entry point:

      discovery   factory/discovery/Invoke-Discovery.ps1   (read-only)
      broker      bootstrap-broker.ps1                     (plan-first, -Apply-gated)
      render      Invoke-LzRender (factory/renderer)       (staging-only)
      scaffold    scaffold-copy.ps1                        (plan-first, -Apply-gated)

    Phase-gating semantics:
      - Phases run in order and the wrapper STOPS on the first failure, naming
        the failing phase. Later phases are not attempted.
      - Without -Apply everything is plan-first: discovery is read-only by
        design, the broker and scaffold emit plan/audit evidence without
        touching Entra, RBAC, GitHub, or the backend, and the renderer writes
        only to its staging directory (it has no apply concept).
      - -Apply propagates to the broker and the scaffold ONLY. Discovery and
        render never mutate external systems regardless.
      - Discovery readiness gates an apply run: when -Apply is given (and
        -AllowNotReady is not) discovery runs with -FailOnNotReady, so a tenant
        with blocking findings stops the engagement before the broker. In plan
        mode discovery findings are reported but do not stop the sequence.
      - Running a single -Phase validates that phase's inputs first and fails
        with the name of the phase that must produce them.

    Environment variables of the underlying tools are honored where the tool
    genuinely reads them: the wrapper resolves LZ_BOOTSTRAP_OUTPUT,
    LZ_RENDERED_PATH, LZ_SCAFFOLD_TARGET, and LZ_SCAFFOLD_EVIDENCE the same way
    the tools do and passes the resolved value through, so the evidence
    locations it prints are the locations the tools used. Apply-mode variables
    (LZ_BOOTSTRAP_APPLY, LZ_SCAFFOLD_APPLY) keep their native behavior inside
    each tool.

    Exception - the discovery -> broker hand-off: Invoke-Discovery.ps1 reads no
    environment variables and always writes discovery-inventory.json beside the
    config file, so the wrapper pins the broker's -DiscoveryPath to that
    location. A set-but-different LZ_DISCOVERY_PATH is reported as IGNORED for
    the hand-off (it would point the broker at another engagement's inventory
    while the fresh output sat unread); it still applies when you run
    bootstrap-broker.ps1 directly.

.PARAMETER ConfigPath
    Path to the wizard-exported lz-config.json. Required.

.PARAMETER Phase
    Which phase to run: discovery, broker, render, scaffold, or all (default).

.PARAMETER Apply
    Propagated to the broker and the scaffold. Without it, every phase is
    plan/evidence only.

.PARAMETER AllowNotReady
    Propagated to the broker, and relaxes the discovery readiness gate on an
    apply run. Use only with an approved exception.

.PARAMETER Force
    Propagated to the renderer (permit writing into a non-empty staging
    directory) and to the scaffold.

.EXAMPLE
    ./scripts/Invoke-CustomerEngagement.ps1 -ConfigPath ./generated-output/contoso/lz-config.json

    Plan-first end-to-end run: discovery report, bootstrap plan, rendered
    staging tree, scaffold plan. Nothing external is modified.

.EXAMPLE
    ./scripts/Invoke-CustomerEngagement.ps1 -ConfigPath ./generated-output/contoso/lz-config.json -Phase broker -Apply

    Re-run only the (idempotent) broker, this time reconciling for real.

.NOTES
    Exit code 0 on success; 1 on the first failing phase, which is named in the
    output together with the evidence files produced up to that point.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('discovery', 'broker', 'render', 'scaffold', 'all')]
    [string]$Phase = 'all',
    [switch]$Apply,
    [switch]$AllowNotReady,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-LzEngagementEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    Write-LzEngagementEvent FAIL "Configuration not found: $ConfigPath"
    exit 1
}
$configFullPath = (Resolve-Path $ConfigPath).Path
$configDirectory = Split-Path -Parent $configFullPath

# Resolve the SAME defaults the underlying tools resolve, so the evidence
# locations reported here are the locations the tools actually used.
#
# Discovery is the exception: Invoke-Discovery.ps1 reads no environment
# variables and always writes beside the config file, so the discovery ->
# broker hand-off is pinned to that location. Honoring LZ_DISCOVERY_PATH here
# would make the broker read a stale/other-engagement inventory while the
# fresh discovery output sat unread.
$discoveryOutputPath = Join-Path $configDirectory 'discovery-inventory.json'
if ($env:LZ_DISCOVERY_PATH) {
    $normalizedEnvDiscovery = [System.IO.Path]::GetFullPath($env:LZ_DISCOVERY_PATH, (Get-Location).Path)
    if (-not $normalizedEnvDiscovery.Equals([System.IO.Path]::GetFullPath($discoveryOutputPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-LzEngagementEvent WARN "LZ_DISCOVERY_PATH ('$($env:LZ_DISCOVERY_PATH)') is IGNORED for the discovery -> broker hand-off: Invoke-Discovery.ps1 always writes beside the config file, so the broker is pointed at '$discoveryOutputPath'. Unset the variable, or run bootstrap-broker.ps1 directly if you really mean to use a different inventory."
    }
}
$bootstrapOutput = if ($env:LZ_BOOTSTRAP_OUTPUT) { $env:LZ_BOOTSTRAP_OUTPUT } else { './bootstrap-output' }
$renderedPath = if ($env:LZ_RENDERED_PATH) { $env:LZ_RENDERED_PATH } else { './rendered-output' }
$scaffoldTarget = if ($env:LZ_SCAFFOLD_TARGET) { $env:LZ_SCAFFOLD_TARGET } else { './scaffold-output' }
$scaffoldEvidence = if ($env:LZ_SCAFFOLD_EVIDENCE) { $env:LZ_SCAFFOLD_EVIDENCE } else { './scaffold-evidence' }

$phaseSequence = if ($Phase -eq 'all') { @('discovery', 'broker', 'render', 'scaffold') } else { @($Phase) }
$mode = if ($Apply) { 'apply (broker + scaffold)' } else { 'plan-first (no -Apply)' }
Write-LzEngagementEvent INFO "Engagement run: phases [$($phaseSequence -join ' -> ')], mode: $mode"
Write-LzEngagementEvent INFO "Configuration: $configFullPath"

$evidence = [ordered]@{}

function Invoke-EngagementDiscovery {
    $splat = @{ ConfigPath = $configFullPath }
    if ($Apply -and -not $AllowNotReady) {
        # Readiness gates an apply run; a plan run only reports.
        $splat.FailOnNotReady = $true
    }
    & (Join-Path $repoRoot 'factory/discovery/Invoke-Discovery.ps1') @splat
    if ($LASTEXITCODE -ne 0) {
        throw "Discovery reported the tenant as not ready (exit $LASTEXITCODE). See tenant-readiness-report.md; use -AllowNotReady only with an approved exception."
    }
    $evidence['discovery'] = @(
        $discoveryOutputPath
        (Join-Path $configDirectory 'tenant-readiness-report.md')
    )
}

function Invoke-EngagementBroker {
    if (-not (Test-Path $discoveryOutputPath -PathType Leaf)) {
        throw "Discovery inventory not found: $discoveryOutputPath. Run the 'discovery' phase first."
    }
    & (Join-Path $repoRoot 'bootstrap-broker.ps1') `
        -ConfigPath $configFullPath `
        -DiscoveryPath $discoveryOutputPath `
        -OutputDirectory $bootstrapOutput `
        -Apply:$Apply `
        -AllowNotReady:$AllowNotReady | Out-Null
    $evidence['broker'] = @(
        (Join-Path $bootstrapOutput 'bootstrap-plan.json')
        (Join-Path $bootstrapOutput 'bootstrap-audit.json')
    )
}

function Invoke-EngagementRender {
    Import-Module (Join-Path $repoRoot 'factory/renderer/LZFactory.Renderer.psd1') -Force
    $splat = @{
        ConfigPath      = $configFullPath
        OutputDirectory = $renderedPath
        Force           = [bool]$Force
    }
    if (Test-Path $discoveryOutputPath -PathType Leaf) {
        # Optional input: brownfield-aware rendering when discovery has run.
        $splat.DiscoveryPath = $discoveryOutputPath
    }
    Invoke-LzRender @splat | Out-Null
    $evidence['render'] = @((Join-Path $renderedPath 'render-manifest.json'))
}

function Invoke-EngagementScaffold {
    $renderManifest = Join-Path $renderedPath 'render-manifest.json'
    if (-not (Test-Path $renderManifest -PathType Leaf)) {
        throw "Renderer inventory not found: $renderManifest. Run the 'render' phase first (or set LZ_RENDERED_PATH)."
    }
    & (Join-Path $repoRoot 'scaffold-copy.ps1') `
        -ConfigPath $configFullPath `
        -RenderedDirectory $renderedPath `
        -TargetDirectory $scaffoldTarget `
        -EvidenceDirectory $scaffoldEvidence `
        -Apply:$Apply `
        -Force:$Force | Out-Null
    $evidence['scaffold'] = @(
        (Join-Path $scaffoldEvidence 'scaffold-plan.json')
        (Join-Path $scaffoldEvidence 'scaffold-audit.json')
    )
}

function Write-EngagementEvidence {
    foreach ($phaseName in $evidence.Keys) {
        foreach ($file in $evidence[$phaseName]) {
            $marker = if (Test-Path $file) { 'OK' } else { 'WARN' }
            Write-LzEngagementEvent $marker ("  {0,-10} {1}" -f $phaseName, $file)
        }
    }
}

foreach ($currentPhase in $phaseSequence) {
    Write-LzEngagementEvent INFO ('-' * 72)
    Write-LzEngagementEvent INFO "Phase: $currentPhase"
    try {
        switch ($currentPhase) {
            'discovery' { Invoke-EngagementDiscovery }
            'broker' { Invoke-EngagementBroker }
            'render' { Invoke-EngagementRender }
            'scaffold' { Invoke-EngagementScaffold }
        }
        Write-LzEngagementEvent OK "Phase '$currentPhase' completed."
    }
    catch {
        Write-LzEngagementEvent FAIL "Phase '$currentPhase' failed: $($_.Exception.Message)"
        if ($evidence.Keys.Count) {
            Write-LzEngagementEvent INFO 'Evidence produced before the failure:'
            Write-EngagementEvidence
        }
        exit 1
    }
}

Write-LzEngagementEvent INFO ('-' * 72)
Write-LzEngagementEvent OK "All requested phases completed ($mode)."
Write-LzEngagementEvent INFO 'Evidence files:'
Write-EngagementEvidence
exit 0
