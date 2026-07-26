#Requires -Version 7.0
<#
.SYNOPSIS
    Stage 12 credential-free Factory CI orchestrator.
.DESCRIPTION
    Runs the complete factory contract and writes factory-ci-report.json.
    This script validates source only. It contains no Azure login, Terraform
    plan/apply/import/state, GitHub write, or customer-repository mutation.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = $(if ($env:LZ_FACTORY_CI_OUTPUT) { $env:LZ_FACTORY_CI_OUTPUT } else { 'factory-ci-output' }),
    [switch]$FailFast,
    [switch]$SkipTerraform,
    [switch]$SkipStatic
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$failFastRequested = $FailFast -or $env:LZ_FACTORY_CI_FAIL_FAST -eq 'true'
$skipTerraformRequested = $SkipTerraform -or $env:LZ_FACTORY_CI_SKIP_TERRAFORM -eq 'true'
$skipStaticRequested = $SkipStatic -or $env:LZ_FACTORY_CI_SKIP_STATIC -eq 'true'
$terraformRoots = if ($env:LZ_FACTORY_CI_TERRAFORM_ROOTS) {
    @($env:LZ_FACTORY_CI_TERRAFORM_ROOTS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    @('factory/templates/terraform')
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
$started = Get-Date
$fatalError = $null

function Invoke-LzFactoryCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [string]$WorkingDirectory = $repo,
        [string]$Category = 'contract'
    )
    $checkStarted = Get-Date
    $output = @()
    $exitCode = 1
    $errorText = $null
    try {
        Push-Location $WorkingDirectory
        $output = @(& $Command @Arguments 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    }
    catch {
        $errorText = $_.Exception.Message
        $output += $errorText
        $exitCode = 1
    }
    finally {
        Pop-Location
    }
    $logName = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') + '.log'
    $logPath = Join-Path $OutputDirectory $logName
    $output | Set-Content $logPath -Encoding utf8
    $result = [pscustomobject]@{
        name = $Name
        category = $Category
        status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        exitCode = $exitCode
        startedAt = $checkStarted.ToUniversalTime().ToString('o')
        durationSeconds = [math]::Round(((Get-Date) - $checkStarted).TotalSeconds, 3)
        log = $logName
        error = $errorText
    }
    $results.Add($result)
    $mark = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host "[$mark] $Name"
    if ($exitCode -ne 0 -and $failFastRequested) {
        throw "Factory CI fail-fast: $Name"
    }
    return $result
}

function Test-LzCommand {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required Factory CI command is unavailable: $Name"
    }
}

try {
    foreach ($command in @('node', 'pwsh')) { Test-LzCommand $command }

    Invoke-LzFactoryCheck 'Wizard tests' node @('factory/tests/test.js') -Category 'tests' | Out-Null
    foreach ($suite in @(
        'Test-Discovery.ps1',
        'Test-Renderer.ps1',
        'Test-Bootstrap.ps1',
        'Test-Scaffold.ps1',
        'Test-Import.ps1',
        'Test-CI.ps1'
    )) {
        Invoke-LzFactoryCheck $suite pwsh @('-NoLogo', '-NoProfile', '-File', "factory/tests/$suite") -Category 'tests' | Out-Null
    }

    $driftCommand = @'
Import-Module ./factory/renderer/LZFactory.Renderer.psd1 -Force
$result = Test-LzSchemaDrift -SchemaPath ./factory/schema/lz-config.schema.json -MappingPath ./factory/renderer/variable-map.json -TemplateRoot ./factory/templates
$result | ConvertTo-Json -Depth 20
if (-not $result.InSync) { exit 1 }
'@
    Invoke-LzFactoryCheck 'Schema variable drift' pwsh @('-NoLogo', '-NoProfile', '-Command', $driftCommand) -Category 'contract' | Out-Null
    Invoke-LzFactoryCheck 'Site no network' pwsh @('-NoLogo', '-NoProfile', '-File', 'factory/ci/Test-SiteNoNetwork.ps1') -Category 'policy' | Out-Null
    Invoke-LzFactoryCheck 'Action pinning' pwsh @('-NoLogo', '-NoProfile', '-File', 'factory/ci/Test-ActionPins.ps1') -Category 'policy' | Out-Null

    if (-not $skipStaticRequested) {
        Test-LzCommand 'shellcheck'
        $shellFiles = @(Get-ChildItem $repo -Recurse -File -Filter '*.sh' |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|generated-output|node_modules)[\\/]' } |
            ForEach-Object { $_.FullName })
        if ($shellFiles.Count -gt 0) {
            Invoke-LzFactoryCheck 'ShellCheck' shellcheck (@('-S', 'error') + $shellFiles) -Category 'static-analysis' | Out-Null
        }
        $analyzerCommand = @'
Import-Module PSScriptAnalyzer -ErrorAction Stop
$paths = Get-ChildItem . -Recurse -File -Include *.ps1,*.psm1 |
    Where-Object { $_.FullName -notmatch '[\\/](generated-output|node_modules)[\\/]' }
$findings = @($paths | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error })
$findings | Format-Table -AutoSize | Out-String | Write-Host
if ($findings.Count -gt 0) { exit 1 }
'@
        Invoke-LzFactoryCheck 'PSScriptAnalyzer' pwsh @('-NoLogo', '-NoProfile', '-Command', $analyzerCommand) -Category 'static-analysis' | Out-Null
    }

    if (-not $skipTerraformRequested) {
        Test-LzCommand 'terraform'
        foreach ($relativeRoot in $terraformRoots) {
            $root = Join-Path $repo $relativeRoot
            if (-not (Test-Path $root -PathType Container)) { throw "Terraform root not found: $relativeRoot" }
            Invoke-LzFactoryCheck "Terraform fmt $relativeRoot" terraform @('fmt', '-check', '-recursive', $root) -Category 'terraform' | Out-Null
            $directories = @(Get-ChildItem $root -Recurse -File -Filter '*.tf' |
                ForEach-Object DirectoryName | Sort-Object -Unique)
            foreach ($directory in $directories) {
                $display = $directory.Substring($repo.Length).TrimStart('\', '/')
                Invoke-LzFactoryCheck "Terraform init $display" terraform @('init', '-backend=false', '-input=false', '-no-color') $directory 'terraform' | Out-Null
                Invoke-LzFactoryCheck "Terraform validate $display" terraform @('validate', '-no-color') $directory 'terraform' | Out-Null
            }
        }
    }
}
catch {
    $fatalError = $_.Exception.Message
    $results.Add([pscustomobject]@{
        name = 'Factory CI infrastructure'
        category = 'infrastructure'
        status = 'failed'
        exitCode = 1
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        durationSeconds = 0
        log = $null
        error = $fatalError
    })
    Write-Host "[FAIL] $fatalError"
}
finally {
    $failed = @($results | Where-Object status -eq 'failed')
    $report = [ordered]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        startedAt = $started.ToUniversalTime().ToString('o')
        durationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        repository = $repo
        failFast = $failFastRequested
        skipped = [ordered]@{
            terraform = $skipTerraformRequested
            staticAnalysis = $skipStaticRequested
        }
        terraformRoots = $terraformRoots
        checkCount = $results.Count
        passedCount = @($results | Where-Object status -eq 'passed').Count
        failedCount = $failed.Count
        success = $failed.Count -eq 0
        checks = @($results)
        externalMutation = $false
        fatalError = $fatalError
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $OutputDirectory 'factory-ci-report.json') -Encoding utf8
}

if (@($results | Where-Object status -eq 'failed').Count -gt 0) { exit 1 }
exit 0
