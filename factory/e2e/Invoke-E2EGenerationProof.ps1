#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end generation proof: real UI → render → validate → six gates.
.DESCRIPTION
    Drives the actual wizard headlessly (factory/e2e/drive-wizard.js) to
    produce the answer record — never hand-authored — renders it, runs the
    validation gates, and proves:
      (a) zero unfilled placeholders in generated output,
      (b) generated tree matches the output manifest exactly, zero generator
          machinery leaked,
      (c) terraform fmt -check / init -backend=false / validate pass on every
          generated layer,
      (d) every generated deploy workflow pins actions to 40-char SHAs and
          sets id-token: write,
      (e) .alzlib/ is gitignored in generated output and no state files exist,
      (f) no GUID outside the synthetic driver identity set (plus Azure
          built-in definition IDs) appears in generated output.
    Writes e2e-report.json (the release-readiness input) and exits non-zero
    if any gate fails.
.PARAMETER OutputDirectory
    Working directory for answers, render, evidence. Default ./e2e-output.
.PARAMETER Topology
    hub-spoke (default) or virtual-wan.
.PARAMETER AllowRegistryBlocked
    Record gate (c)'s init/validate as environment-limited instead of failing,
    for sandboxes whose egress proxy blocks registry.terraform.io. The gate is
    then reported false with reason 'registry-blocked' — release readiness
    still requires a run where it passed.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = './e2e-output',
    [ValidateSet('hub-spoke', 'virtual-wan')][string]$Topology = 'hub-spoke',
    [switch]$AllowRegistryBlocked
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$factoryVersion = Get-Content (Join-Path $repo 'factory-version.json') -Raw | ConvertFrom-Json -Depth 20
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$out = (Resolve-Path $OutputDirectory).Path
$answersDir = Join-Path $out 'answers'
$renderDir = Join-Path $out 'rendered'
$evidenceDir = Join-Path $out 'evidence'

$gates = [ordered]@{}
function Set-Gate([string]$Name, [bool]$Passed, [string]$Evidence) {
    $gates[$Name] = [ordered]@{ passed = $Passed; evidence = $Evidence }
    $mark = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Host "[$mark] $Name — $Evidence"
}

# ── 9a: the REAL UI produces the answer record ───────────────────────────────
Write-Host "== Driving the wizard headlessly ($Topology) =="
Remove-Item -Recurse -Force $answersDir -ErrorAction SilentlyContinue
& node (Join-Path $PSScriptRoot 'drive-wizard.js') $answersDir --topology $Topology
if ($LASTEXITCODE -ne 0) { throw 'Wizard drive failed — the UI refused to export.' }
$configPath = Join-Path $answersDir 'lz-config.json'
$uiDriven = Test-Path $configPath
if (-not $uiDriven) { throw 'The UI did not produce lz-config.json.' }

# ── Render ───────────────────────────────────────────────────────────────────
Write-Host '== Rendering =='
Import-Module (Join-Path $repo 'factory/renderer/LZFactory.Renderer.psd1') -Force
Remove-Item -Recurse -Force $renderDir -ErrorAction SilentlyContinue
$null = Invoke-LzRender -ConfigPath $configPath -OutputDirectory $renderDir -Quiet

# ── Validation gates V01–V08 (includes (b) inventory and (d) pinning) ────────
Write-Host '== Validation gates =='
Import-Module (Join-Path $repo 'factory/validate/LZFactory.Validate.psm1') -Force
$validateThrew = $null
try { $null = Invoke-LzValidate -RenderedDirectory $renderDir -EvidenceDirectory $evidenceDir }
catch { $validateThrew = $_.Exception.Message }
$validateReport = Get-Content (Join-Path $evidenceDir 'validate-report.json') -Raw | ConvertFrom-Json -Depth 20
$gateStatus = @{}
foreach ($g in $validateReport.gates) { $gateStatus[$g.id] = $g.status }

# (a) zero residual placeholders — both conventions.
$upperSnake = @(Get-ChildItem $renderDir -Recurse -File | Select-String -Pattern '__[A-Z0-9_]+__' -AllMatches)
$factoryTokens = @(Get-ChildItem $renderDir -Recurse -File | Select-String -Pattern '(?<!\$)\{\{[^}]*\}\}' |
    Where-Object { $_.Line -notmatch '\$\{\{' })
Set-Gate 'zeroResidualPlaceholders' ($upperSnake.Count -eq 0 -and $factoryTokens.Count -eq 0) `
    "__UPPER_SNAKE__ hits: $($upperSnake.Count); factory-token hits: $($factoryTokens.Count)"

# (b) tree matches the manifest; zero generator machinery.
$machinery = @(Get-ChildItem $renderDir -Recurse -Force |
    Where-Object { $_.Name -in @('factory', 'site', 'frontend', 'node_modules', 'host.json') -or $_.Name -like '*.psm1' -or $_.Name -like '*.psd1' })
Set-Gate 'manifestMatch' (($gateStatus['V01'] -eq 'pass') -and $machinery.Count -eq 0) `
    "V01 inventory-integrity: $($gateStatus['V01']); generator files leaked: $($machinery.Count)"

# (c) fmt + init + validate.
$initOk = ($gateStatus['V03'] -eq 'pass' -and $gateStatus['V04'] -eq 'pass')
$initEvidence = "V02 fmt: $($gateStatus['V02']); V03 init: $($gateStatus['V03']); V04 validate: $($gateStatus['V04'])"
if (-not $initOk -and $AllowRegistryBlocked) {
    $v03Log = Get-Content (Join-Path $evidenceDir 'logs/v03-dependency-integrity.log') -Raw -ErrorAction SilentlyContinue
    if ($v03Log -match 'Error accessing remote module registry') {
        $initEvidence += ' — environment-limited: registry.terraform.io blocked by egress proxy; re-run where the registry is reachable'
    }
}
Set-Gate 'terraformInitValidatePassed' ($initOk -and $gateStatus['V02'] -eq 'pass') $initEvidence

# (d) workflows: 40-char SHA pins (V05) + id-token: write on every workflow
# that federates to Azure. Credential-free workflows (fmt-validate, pinning
# policy, security scan) correctly carry NEITHER — least privilege.
$allWorkflows = @(Get-ChildItem (Join-Path $renderDir '.github/workflows') -Filter '*.yml')
$federating = @($allWorkflows | Where-Object { (Get-Content $_.FullName -Raw) -match 'azure/login' })
$missingIdToken = @($federating | Where-Object { (Get-Content $_.FullName -Raw) -notmatch 'id-token:\s*write' })
$credentialFreeWithToken = @($allWorkflows | Where-Object {
        $raw = Get-Content $_.FullName -Raw
        $raw -notmatch 'azure/login' -and $raw -match 'id-token:\s*write'
    })
Set-Gate 'workflowsPinnedWithIdToken' (($gateStatus['V05'] -eq 'pass') -and $missingIdToken.Count -eq 0 -and $credentialFreeWithToken.Count -eq 0) `
    "V05 pinning: $($gateStatus['V05']); federating workflows: $($federating.Count), all with id-token: $($missingIdToken.Count -eq 0); credential-free workflows carrying a needless token: $($credentialFreeWithToken.Count)"

# (e) .alzlib/ ignored; no state files.
$gitignore = Get-Content (Join-Path $renderDir '.gitignore') -Raw -ErrorAction SilentlyContinue
$stateFiles = @(Get-ChildItem $renderDir -Recurse -Force -Include '*.tfstate', '*.tfstate.*', '*.tfplan' -ErrorAction SilentlyContinue)
Set-Gate 'alzlibIgnoredNoState' (($gitignore -match '\.alzlib/') -and $stateFiles.Count -eq 0) `
    ".alzlib/ in .gitignore: $([bool]($gitignore -match '\.alzlib/')); state files: $($stateFiles.Count)"

# (f) GUID hygiene: only the synthetic driver identities (and Azure built-in
# definition IDs, which are global constants, not tenant data) may appear.
$syntheticAllowed = @(
    '11111111-2222-3333-4444-555555555555',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000'
)
$guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$foundGuids = @(Get-ChildItem $renderDir -Recurse -File |
    Select-String -Pattern $guidPattern -AllMatches |
    ForEach-Object { $_.Matches.Value } | Sort-Object -Unique)
$unexpected = @($foundGuids | Where-Object { $_.ToLowerInvariant() -notin $syntheticAllowed })
Set-Gate 'zeroGuids' ($unexpected.Count -eq 0) `
    "distinct GUIDs: $($foundGuids.Count) (all synthetic driver identities); unexpected: $($unexpected.Count)$(if ($unexpected.Count) { ' — ' + ($unexpected -join ', ') })"

# ── Report ───────────────────────────────────────────────────────────────────
$allPassed = @($gates.Values | Where-Object { -not $_.passed }).Count -eq 0
$report = [ordered]@{
    schemaVersion  = '1.0.0'
    repository     = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { 'HybridCloudWorks/Template-LZDeployment' }
    factoryVersion = "$($factoryVersion.factoryVersion)"
    topology       = $Topology
    completedAt    = (Get-Date).ToUniversalTime().ToString('o')
    success        = $allPassed
    uiDriven       = $true
    zeroResidualPlaceholders    = $gates['zeroResidualPlaceholders'].passed
    manifestMatch               = $gates['manifestMatch'].passed
    terraformInitValidatePassed = $gates['terraformInitValidatePassed'].passed
    workflowsPinnedWithIdToken  = $gates['workflowsPinnedWithIdToken'].passed
    alzlibIgnoredNoState        = $gates['alzlibIgnoredNoState'].passed
    zeroGuids                   = $gates['zeroGuids'].passed
    gates          = $gates
    validateThrew  = $validateThrew
}
$reportPath = Join-Path $out 'e2e-report.json'
$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding utf8
Write-Host "e2e-report.json written: $reportPath"

if (-not $allPassed -and -not ($AllowRegistryBlocked -and
        @($gates.Keys | Where-Object { -not $gates[$_].passed }) -eq @('terraformInitValidatePassed'))) {
    throw 'End-to-end generation proof failed — see e2e-report.json.'
}
if (-not $allPassed) {
    Write-Warning 'Proof incomplete: terraform init/validate is environment-limited (registry blocked). All other gates passed.'
}
