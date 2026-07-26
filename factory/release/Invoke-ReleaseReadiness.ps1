#Requires -Version 7.0
<#
    Stage 14 release evidence attestation and promotion planning.

    This command reads existing evidence only. It never contacts Azure, GitHub,
    or HCP Terraform and never edits factory-version.json. A successful report
    is a review input, not an automatic release or v1.0.0 declaration.
#>
[CmdletBinding()]
param(
    [string]$FactoryCiReport = $env:LZ_RELEASE_FACTORY_CI_REPORT,
    [string]$DogfoodReport = $env:LZ_RELEASE_DOGFOOD_REPORT,
    [string]$AttestationPath = $env:LZ_RELEASE_ATTESTATION_PATH,
    [string]$OutputDirectory = $env:LZ_RELEASE_EVIDENCE,
    [switch]$AllowIncomplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LzReleaseValue {
    param([string]$Value, [string]$EnvironmentName, [string]$Default = '')
    if (-not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $candidate = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
    return $Default
}

function ConvertTo-LzReleaseBoolean {
    param([string]$Value)
    return "$Value" -match '^(1|true|yes|on)$'
}

function Get-LzReleaseHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LzReleaseCheck {
    param([Parameter(Mandatory)][object]$Report, [Parameter(Mandatory)][string]$Name)
    return @($Report.checks | Where-Object { "$($_.name)" -eq $Name } | Select-Object -First 1)
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$FactoryCiReport = Get-LzReleaseValue $FactoryCiReport 'LZ_RELEASE_FACTORY_CI_REPORT'
$DogfoodReport = Get-LzReleaseValue $DogfoodReport 'LZ_RELEASE_DOGFOOD_REPORT'
$AttestationPath = Get-LzReleaseValue $AttestationPath 'LZ_RELEASE_ATTESTATION_PATH'
$OutputDirectory = Get-LzReleaseValue $OutputDirectory 'LZ_RELEASE_EVIDENCE' (Join-Path $repo 'release-evidence')
$allowIncompleteRequested = $AllowIncomplete -or
    (ConvertTo-LzReleaseBoolean $env:LZ_RELEASE_ALLOW_INCOMPLETE)
$expectedRepository = Get-LzReleaseValue '' 'LZ_RELEASE_EXPECTED_REPOSITORY' 'saulpatinojr/HCW-Plan_LZDeployment'
$maximumAgeHours = [int](Get-LzReleaseValue '' 'LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS' '168')
if ($maximumAgeHours -lt 1) {
    throw 'LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS must be a positive integer.'
}

foreach ($input in @(
    @{ Name = 'Factory CI report'; Path = $FactoryCiReport },
    @{ Name = 'Dogfood report'; Path = $DogfoodReport },
    @{ Name = 'Release attestation'; Path = $AttestationPath }
)) {
    if ([string]::IsNullOrWhiteSpace($input.Path) -or -not (Test-Path $input.Path -PathType Leaf)) {
        throw "$($input.Name) is required and must be an existing file."
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$factoryVersion = Get-Content (Join-Path $repo 'factory-version.json') -Raw | ConvertFrom-Json -Depth 20
$factory = Get-Content $FactoryCiReport -Raw | ConvertFrom-Json -Depth 50
$dogfood = Get-Content $DogfoodReport -Raw | ConvertFrom-Json -Depth 50
$attestation = Get-Content $AttestationPath -Raw | ConvertFrom-Json -Depth 20
$requiredAttestationProperties = @(
    'schemaVersion', 'repository', 'factoryVersion', 'issuedAt', 'reviewer',
    'approvalReference', 'factoryCiReportSha256', 'dogfoodReportSha256',
    'dogfoodReadBackVerified', 'oidcTokenExchangeVerifiedLive',
    'allEmittedModulesImplemented', 'branchProtectionVerified'
)
$allowedAttestationProperties = @($requiredAttestationProperties + 'notes')
$actualAttestationProperties = @($attestation.PSObject.Properties.Name)
$missingAttestationProperties = @(
    $requiredAttestationProperties | Where-Object { $_ -notin $actualAttestationProperties }
)
$unexpectedAttestationProperties = @(
    $actualAttestationProperties | Where-Object { $_ -notin $allowedAttestationProperties }
)
if ($missingAttestationProperties.Count -gt 0 -or $unexpectedAttestationProperties.Count -gt 0) {
    throw "Release attestation contract mismatch. Missing: $($missingAttestationProperties -join ', '); unexpected: $($unexpectedAttestationProperties -join ', ')"
}
if ("$($attestation.schemaVersion)" -ne '1.0.0' -or
    "$($attestation.factoryCiReportSha256)" -notmatch '^[a-f0-9]{64}$' -or
    "$($attestation.dogfoodReportSha256)" -notmatch '^[a-f0-9]{64}$') {
    throw 'Release attestation schema version or SHA-256 format is invalid.'
}
foreach ($booleanProperty in @(
    'dogfoodReadBackVerified', 'oidcTokenExchangeVerifiedLive',
    'allEmittedModulesImplemented', 'branchProtectionVerified'
)) {
    if ($attestation.$booleanProperty -isnot [bool]) {
        throw "Release attestation property '$booleanProperty' must be a JSON boolean."
    }
}
$factoryHash = Get-LzReleaseHash $FactoryCiReport
$dogfoodHash = Get-LzReleaseHash $DogfoodReport
$now = (Get-Date).ToUniversalTime()

$findings = [Collections.Generic.List[object]]::new()
function Add-LzReleaseFinding {
    param([string]$Id, [string]$Description, [bool]$Passed, [string]$Evidence)
    $findings.Add([pscustomobject]@{
        id = $Id
        description = $Description
        status = if ($Passed) { 'passed' } else { 'failed' }
        evidence = $Evidence
    })
}

$factoryCompleted = [datetime]::Parse("$($factory.generatedAt)").ToUniversalTime()
$dogfoodCompleted = [datetime]::Parse("$($dogfood.completedAt)").ToUniversalTime()
$attestedAt = [datetime]::Parse("$($attestation.issuedAt)").ToUniversalTime()
$factoryAge = ($now - $factoryCompleted).TotalHours
$dogfoodAge = ($now - $dogfoodCompleted).TotalHours
$attestationAge = ($now - $attestedAt).TotalHours
$factoryFresh = $factoryAge -ge 0 -and $factoryAge -le $maximumAgeHours
$dogfoodFresh = $dogfoodAge -ge 0 -and $dogfoodAge -le $maximumAgeHours
$attestationFresh = $attestationAge -ge 0 -and $attestationAge -le $maximumAgeHours

Add-LzReleaseFinding 'R01' 'Factory CI report targets the current factory version.' `
    ("$($factory.factoryVersion)" -eq "$($factoryVersion.factoryVersion)") "$($factory.factoryVersion)"
Add-LzReleaseFinding 'R02' 'Factory CI completed successfully without skipped checks.' `
    ([bool]$factory.success -and -not [bool]$factory.skipped.terraform -and -not [bool]$factory.skipped.staticAnalysis) `
    "success=$($factory.success); terraformSkipped=$($factory.skipped.terraform); staticSkipped=$($factory.skipped.staticAnalysis)"
Add-LzReleaseFinding 'R03' 'Factory CI evidence is within the allowed age.' $factoryFresh `
    "completed=$($factoryCompleted.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R04' 'Dogfood report targets this repository and current factory version.' `
    ("$($dogfood.repository)" -eq $expectedRepository -and
     "$($dogfood.factoryVersion)" -eq "$($factoryVersion.factoryVersion)") `
    "repository=$($dogfood.repository); version=$($dogfood.factoryVersion)"
Add-LzReleaseFinding 'R05' 'Dogfood is a successful full protected apply eligible for release evidence.' `
    ([bool]$dogfood.success -and "$($dogfood.mode)" -eq 'apply' -and
     "$($dogfood.requestedLayer)" -eq 'all' -and [bool]$dogfood.externalMutation -and
     [bool]$dogfood.releaseGateEligible) `
    "success=$($dogfood.success); mode=$($dogfood.mode); layer=$($dogfood.requestedLayer)"
Add-LzReleaseFinding 'R06' 'Dogfood evidence is within the allowed age.' $dogfoodFresh `
    "completed=$($dogfoodCompleted.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R07' 'Attestation identity and approval metadata are complete.' `
    ("$($attestation.repository)" -eq $expectedRepository -and
     "$($attestation.factoryVersion)" -eq "$($factoryVersion.factoryVersion)" -and
     -not [string]::IsNullOrWhiteSpace("$($attestation.reviewer)") -and
     -not [string]::IsNullOrWhiteSpace("$($attestation.approvalReference)")) `
    "reviewer=$($attestation.reviewer); approval=$($attestation.approvalReference)"
Add-LzReleaseFinding 'R08' 'Attestation is pinned to the exact input evidence.' `
    ("$($attestation.factoryCiReportSha256)" -eq $factoryHash -and
     "$($attestation.dogfoodReportSha256)" -eq $dogfoodHash) `
    "factory=$factoryHash; dogfood=$dogfoodHash"
Add-LzReleaseFinding 'R09' 'Attestation is within the allowed age.' $attestationFresh `
    "issued=$($attestedAt.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R10' 'Independent dogfood and branch-protection read-back is approved.' `
    ([bool]$attestation.dogfoodReadBackVerified -and [bool]$attestation.branchProtectionVerified) `
    "dogfoodReadBack=$($attestation.dogfoodReadBackVerified); branchProtection=$($attestation.branchProtectionVerified)"

$schemaCheck = Get-LzReleaseCheck $factory 'Schema variable drift'
$networkCheck = Get-LzReleaseCheck $factory 'Site no network'
$gates = [ordered]@{
    schemaVariableDriftCheckPasses = (
        $schemaCheck.Count -eq 1 -and "$($schemaCheck[0].status)" -eq 'passed'
    )
    dogfoodInstanceAppliesGreen = (
        [bool]$dogfood.success -and [bool]$dogfood.releaseGateEligible -and
        [bool]$attestation.dogfoodReadBackVerified
    )
    oidcTokenExchangeVerifiedLive = [bool]$attestation.oidcTokenExchangeVerifiedLive
    allEmittedModulesImplemented = [bool]$attestation.allEmittedModulesImplemented
    siteMakesZeroNetworkRequests = (
        $networkCheck.Count -eq 1 -and "$($networkCheck[0].status)" -eq 'passed'
    )
}

$allFindingsPassed = @($findings | Where-Object status -eq 'failed').Count -eq 0
$allGatesPassed = @($gates.GetEnumerator() | Where-Object { -not $_.Value }).Count -eq 0
$ready = $allFindingsPassed -and $allGatesPassed
$report = [ordered]@{
    schemaVersion = '1.0.0'
    generatedAt = $now.ToString('o')
    repository = $expectedRepository
    factoryVersion = "$($factoryVersion.factoryVersion)"
    evidenceMaximumAgeHours = $maximumAgeHours
    readyForPromotion = $ready
    externalMutation = $false
    sourceEvidence = [ordered]@{
        factoryCiReport = $FactoryCiReport
        factoryCiSha256 = $factoryHash
        dogfoodReport = $DogfoodReport
        dogfoodSha256 = $dogfoodHash
        attestation = $AttestationPath
        attestationSha256 = Get-LzReleaseHash $AttestationPath
    }
    findings = @($findings)
    proposedReleaseGates = $gates
    reviewer = "$($attestation.reviewer)"
    approvalReference = "$($attestation.approvalReference)"
    userActivities = @(
        'Review every input hash, finding, and proposed release gate.',
        'Open a separate pull request for any factory-version.json gate changes.',
        'Do not declare v1.0.0 until all gates are true and independently approved.'
    )
}
$report | ConvertTo-Json -Depth 30 |
    Set-Content (Join-Path $OutputDirectory 'release-readiness-report.json') -Encoding utf8
([ordered]@{
    factoryVersion = "$($factoryVersion.factoryVersion)"
    generatedAt = $now.ToString('o')
    sourceReportSha256 = Get-LzReleaseHash (Join-Path $OutputDirectory 'release-readiness-report.json')
    releaseGates = $gates
}) | ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $OutputDirectory 'release-gates.proposed.json') -Encoding utf8

if (-not $ready -and -not $allowIncompleteRequested) {
    throw 'Release evidence is incomplete. Review release-readiness-report.json.'
}
