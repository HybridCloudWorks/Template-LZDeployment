#Requires -Version 7.0
<#
.SYNOPSIS
    Stage 10 Landing Zone Factory scaffold builder.
.DESCRIPTION
    Verifies a renderer output tree, emits deterministic plan/audit evidence,
    and creates or updates the configured repository only when -Apply (or
    LZ_SCAFFOLD_APPLY=true) is supplied. Apply additionally requires a passing,
    current validate-render.ps1 report for the same render (see
    -ValidationReportPath / LZ_VALIDATE_EVIDENCE). All values are provided by
    config, parameters, or environment variables; this entry point never
    prompts.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = $(if ($env:LZ_CONFIG_PATH) { $env:LZ_CONFIG_PATH } else { './lz-config.json' }),
    [string]$RenderedDirectory = $(if ($env:LZ_RENDERED_PATH) { $env:LZ_RENDERED_PATH } else { './rendered-output' }),
    [string]$TargetDirectory = $(if ($env:LZ_SCAFFOLD_TARGET) { $env:LZ_SCAFFOLD_TARGET } else { './scaffold-output' }),
    [string]$EvidenceDirectory = $(if ($env:LZ_SCAFFOLD_EVIDENCE) { $env:LZ_SCAFFOLD_EVIDENCE } else { './scaffold-evidence' }),
    [string]$ValidationReportPath = $(if ($env:LZ_VALIDATE_EVIDENCE) { Join-Path $env:LZ_VALIDATE_EVIDENCE 'validate-report.json' } else { './validate-evidence/validate-report.json' }),
    [switch]$Apply,
    [switch]$Force,
    [switch]$SkipRepositoryCreate,
    [switch]$SkipPush
)

$module = Join-Path $PSScriptRoot 'factory/scaffold/LZFactory.Scaffold.psm1'
Import-Module $module -Force

$applyRequested = $Apply -or $env:LZ_SCAFFOLD_APPLY -eq 'true'
$forceRequested = $Force -or $env:LZ_SCAFFOLD_FORCE -eq 'true'
$createRepository = -not ($SkipRepositoryCreate -or $env:LZ_SCAFFOLD_CREATE_REPOSITORY -eq 'false')
$pushRepository = -not ($SkipPush -or $env:LZ_SCAFFOLD_PUSH -eq 'false')

Invoke-LzScaffold -ConfigPath $ConfigPath -RenderedDirectory $RenderedDirectory `
    -TargetDirectory $TargetDirectory -EvidenceDirectory $EvidenceDirectory `
    -ValidationReportPath $ValidationReportPath `
    -Apply:$applyRequested -Force:$forceRequested `
    -CreateRepository:$createRepository -Push:$pushRepository
