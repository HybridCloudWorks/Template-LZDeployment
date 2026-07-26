#Requires -Version 7.0
<#
    Stage 13 dogfood orchestrator.

    The runner regenerates an HCW landing-zone instance from the factory, then
    executes a real Terraform plan or an explicitly authorized apply against
    the rendered tree. Configuration and credentials are supplied at runtime;
    no tenant identifiers, tokens, plans, or state are committed.
#>
[CmdletBinding()]
param(
    [ValidateSet('Render', 'Plan', 'Apply')][string]$Mode = 'Render',
    [string]$ConfigPath = $env:LZ_DOGFOOD_CONFIG_PATH,
    [string]$OutputDirectory = $env:LZ_DOGFOOD_OUTPUT,
    [string]$EvidenceDirectory = $env:LZ_DOGFOOD_EVIDENCE,
    [string]$Layer = $env:LZ_DOGFOOD_LAYER,
    [switch]$AllowApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LzDogfoodValue {
    param([string]$Value, [string]$EnvironmentName, [string]$Default = '')
    if (-not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $candidate = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
    return $Default
}

function ConvertTo-LzDogfoodBoolean {
    param([string]$Value)
    return "$Value" -match '^(1|true|yes|on)$'
}

function Resolve-LzDogfoodPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    )
}

function Invoke-LzDogfoodCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogPath
    )
    $old = Get-Location
    try {
        Set-Location $WorkingDirectory
        $output = @(& $Command @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $output | Set-Content -Path $LogPath -Encoding utf8
    }
    finally {
        Set-Location $old
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ConfigPath = Get-LzDogfoodValue $ConfigPath 'LZ_DOGFOOD_CONFIG_PATH'
$OutputDirectory = Get-LzDogfoodValue $OutputDirectory 'LZ_DOGFOOD_OUTPUT' (Join-Path $repoRoot 'dogfood-output')
$EvidenceDirectory = Get-LzDogfoodValue $EvidenceDirectory 'LZ_DOGFOOD_EVIDENCE' (Join-Path $repoRoot 'dogfood-evidence')
$Layer = Get-LzDogfoodValue $Layer 'LZ_DOGFOOD_LAYER' 'all'
$expectedRepository = Get-LzDogfoodValue '' 'LZ_DOGFOOD_REPOSITORY' 'saulpatinojr/HCW-Plan_LZDeployment'
$applyApproved = $AllowApply -or (ConvertTo-LzDogfoodBoolean $env:LZ_DOGFOOD_APPLY)

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw 'LZ_DOGFOOD_CONFIG_PATH or -ConfigPath is required.'
}
if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    throw "Dogfood configuration not found: $ConfigPath"
}
if ($Mode -eq 'Apply' -and -not $applyApproved) {
    throw 'Apply refused. Set LZ_DOGFOOD_APPLY=true only inside an approved protected environment.'
}

$ConfigPath = Resolve-LzDogfoodPath $ConfigPath
$OutputDirectory = Resolve-LzDogfoodPath $OutputDirectory
$EvidenceDirectory = Resolve-LzDogfoodPath $EvidenceDirectory
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$started = (Get-Date).ToUniversalTime()
$checks = [Collections.Generic.List[object]]::new()
$reportPath = Join-Path $EvidenceDirectory 'dogfood-report.json'
$externalMutation = $Mode -eq 'Apply'
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 40
$repository = "$($config.github.ownerName)/$($config.github.repositoryName)"
if ($repository -ne $expectedRepository) {
    throw "Dogfood repository mismatch. Expected '$expectedRepository'; configuration targets '$repository'."
}

try {
    Import-Module (Join-Path $repoRoot 'factory/renderer/LZFactory.Renderer.psd1') -Force
    $renderStart = Get-Date
    Invoke-LzRender -ConfigPath $ConfigPath -OutputDirectory $OutputDirectory -Force -Quiet | Out-Null
    $checks.Add([pscustomobject]@{
        name = 'render'; status = 'passed'; exitCode = 0
        durationSeconds = ((Get-Date) - $renderStart).TotalSeconds
        log = $null
    })

    $manifestPath = Join-Path $OutputDirectory 'render-manifest.json'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 30
    $layers = @($manifest.layers)
    if ($Layer -ne 'all') {
        if ($Layer -notin $layers) { throw "Layer '$Layer' is not in the rendered layer inventory." }
        $layers = @($Layer)
    }
    if ($Mode -eq 'Render') { return }

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw 'terraform is required for Stage 13 plan/apply execution.'
    }

    foreach ($currentLayer in $layers) {
        $layerPath = Join-Path $OutputDirectory "terraform/live/$currentLayer"
        if (-not (Test-Path $layerPath -PathType Container)) {
            throw "Rendered layer directory not found: $layerPath"
        }

        foreach ($operation in @('init', 'plan')) {
            $log = Join-Path $EvidenceDirectory "$currentLayer-$operation.log"
            $args = if ($operation -eq 'init') {
                @('init', '-input=false', '-no-color')
            }
            else {
                @('plan', '-input=false', '-no-color', '-detailed-exitcode', '-out=dogfood.tfplan')
            }
            $timer = Get-Date
            $result = Invoke-LzDogfoodCommand terraform $args $layerPath $log
            $accepted = if ($operation -eq 'plan') { @(0, 2) } else { @(0) }
            $status = if ($result.ExitCode -in $accepted) { 'passed' } else { 'failed' }
            $checks.Add([pscustomobject]@{
                name = "$currentLayer-$operation"; status = $status
                exitCode = $result.ExitCode
                durationSeconds = ((Get-Date) - $timer).TotalSeconds
                log = [IO.Path]::GetRelativePath($EvidenceDirectory, $log) -replace '\\', '/'
            })
            if ($status -eq 'failed') {
                throw "Terraform $operation failed for $currentLayer. See $log"
            }
        }

        $showLog = Join-Path $EvidenceDirectory "$currentLayer-show.log"
        $show = Invoke-LzDogfoodCommand terraform @('show', '-json', 'dogfood.tfplan') $layerPath $showLog
        if ($show.ExitCode -ne 0) { throw "Terraform show failed for $currentLayer." }
        $planJson = ($show.Output -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100
        $destructive = @($planJson.resource_changes | Where-Object {
            @($_.change.actions) -contains 'delete'
        }).Count
        $checks.Add([pscustomobject]@{
            name = "$currentLayer-destructive-change-policy"
            status = if ($destructive -eq 0) { 'passed' } else { 'failed' }
            exitCode = if ($destructive -eq 0) { 0 } else { 1 }
            durationSeconds = 0
            log = [IO.Path]::GetRelativePath($EvidenceDirectory, $showLog) -replace '\\', '/'
            destructiveChanges = $destructive
        })
        if ($destructive -gt 0) {
            throw "Apply refused: $currentLayer plan contains $destructive destructive change(s)."
        }

        if ($Mode -eq 'Apply') {
            $applyLog = Join-Path $EvidenceDirectory "$currentLayer-apply.log"
            $timer = Get-Date
            $apply = Invoke-LzDogfoodCommand terraform @(
                'apply', '-input=false', '-no-color', '-auto-approve', 'dogfood.tfplan'
            ) $layerPath $applyLog
            $checks.Add([pscustomobject]@{
                name = "$currentLayer-apply"
                status = if ($apply.ExitCode -eq 0) { 'passed' } else { 'failed' }
                exitCode = $apply.ExitCode
                durationSeconds = ((Get-Date) - $timer).TotalSeconds
                log = [IO.Path]::GetRelativePath($EvidenceDirectory, $applyLog) -replace '\\', '/'
            })
            if ($apply.ExitCode -ne 0) { throw "Terraform apply failed for $currentLayer." }
        }
    }
}
catch {
    $checks.Add([pscustomobject]@{
        name = 'fatal'; status = 'failed'; exitCode = 1; durationSeconds = 0
        log = $null; message = $_.Exception.Message
    })
    throw
}
finally {
    $ended = (Get-Date).ToUniversalTime()
    $failures = @($checks | Where-Object status -eq 'failed').Count
    $payload = [ordered]@{
        schemaVersion = '1.0.0'
        factoryVersion = if ($config.factoryVersion) { "$($config.factoryVersion)" } else { 'unknown' }
        repository = $repository
        mode = $Mode.ToLowerInvariant()
        requestedLayer = $Layer
        startedAt = $started.ToString('o')
        completedAt = $ended.ToString('o')
        success = $failures -eq 0
        externalMutation = $externalMutation
        releaseGateEligible = ($Mode -eq 'Apply' -and $Layer -eq 'all' -and $failures -eq 0)
        configSha256 = (Get-FileHash $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
        checks = @($checks)
        userActivities = @(
            'Review every plan and apply log.',
            'Read back deployed resources, state, OIDC subjects, and required status checks.',
            'Set dogfoodInstanceAppliesGreen only after independent evidence review.'
        )
    }
    $payload | ConvertTo-Json -Depth 20 | Set-Content $reportPath -Encoding utf8
}
