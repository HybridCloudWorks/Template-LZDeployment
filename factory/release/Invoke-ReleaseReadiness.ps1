#Requires -Version 7.0
<#
    Stage 14 release evidence attestation and promotion planning.

    This command reads existing evidence only. It never contacts Azure, GitHub,
    or the network and never edits factory-version.json. A successful report
    is a review input, not an automatic release or v1.0.0 declaration.
#>
[CmdletBinding()]
param(
    [string]$FactoryCiReport = $env:LZ_RELEASE_FACTORY_CI_REPORT,
    [string]$E2eReport = $env:LZ_RELEASE_E2E_REPORT,
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

function Get-LzReleaseProperty {
    # StrictMode-safe property read: a malformed evidence report must surface
    # as a failed finding, never as a property-access throw.
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-LzReleaseUtcInstant {
    # Culture-invariant round-trip parsing. [datetime]::Parse with the current
    # culture accepts or rejects ISO 8601 timestamps depending on the host's
    # regional settings, which would make readiness evidence machine-dependent.
    param([Parameter(Mandatory)][string]$Value)
    try {
        return [datetime]::Parse(
            $Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
    }
    catch {
        throw "Evidence timestamp '$Value' is not a valid ISO 8601 round-trip datetime."
    }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$FactoryCiReport = Get-LzReleaseValue $FactoryCiReport 'LZ_RELEASE_FACTORY_CI_REPORT'
$E2eReport = Get-LzReleaseValue $E2eReport 'LZ_RELEASE_E2E_REPORT'
$AttestationPath = Get-LzReleaseValue $AttestationPath 'LZ_RELEASE_ATTESTATION_PATH'
$OutputDirectory = Get-LzReleaseValue $OutputDirectory 'LZ_RELEASE_EVIDENCE' (Join-Path $repo 'release-evidence')
$allowIncompleteRequested = $AllowIncomplete -or
    (ConvertTo-LzReleaseBoolean $env:LZ_RELEASE_ALLOW_INCOMPLETE)
$expectedRepository = Get-LzReleaseValue '' 'LZ_RELEASE_EXPECTED_REPOSITORY' 'saulpatinojr/HCW-Plan_LZDeployment'
$maximumAgeHours = [int](Get-LzReleaseValue '' 'LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS' '168')
if ($maximumAgeHours -lt 1) {
    throw 'LZ_RELEASE_MAX_EVIDENCE_AGE_HOURS must be a positive integer.'
}

foreach ($evidenceInput in @(
    @{ Name = 'Factory CI report'; Path = $FactoryCiReport },
    @{ Name = 'E2E generation report'; Path = $E2eReport },
    @{ Name = 'Release attestation'; Path = $AttestationPath }
)) {
    if ([string]::IsNullOrWhiteSpace($evidenceInput.Path) -or -not (Test-Path $evidenceInput.Path -PathType Leaf)) {
        throw "$($evidenceInput.Name) is required and must be an existing file."
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$factoryVersion = Get-Content (Join-Path $repo 'factory-version.json') -Raw | ConvertFrom-Json -Depth 20
$factory = Get-Content $FactoryCiReport -Raw | ConvertFrom-Json -Depth 50
$e2e = Get-Content $E2eReport -Raw | ConvertFrom-Json -Depth 50
$attestation = Get-Content $AttestationPath -Raw | ConvertFrom-Json -Depth 20
$requiredAttestationProperties = @(
    'schemaVersion', 'repository', 'factoryVersion', 'issuedAt', 'reviewer',
    'approvalReference', 'factoryCiReportSha256', 'e2eReportSha256',
    'e2eEvidenceVerified', 'oidcTokenExchangeVerifiedLive',
    'avmPinsVerifiedByInit', 'branchProtectionVerified'
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
    "$($attestation.e2eReportSha256)" -notmatch '^[a-f0-9]{64}$') {
    throw 'Release attestation schema version or SHA-256 format is invalid.'
}
foreach ($booleanProperty in @(
    'e2eEvidenceVerified', 'oidcTokenExchangeVerifiedLive',
    'avmPinsVerifiedByInit', 'branchProtectionVerified'
)) {
    if ($attestation.$booleanProperty -isnot [bool]) {
        throw "Release attestation property '$booleanProperty' must be a JSON boolean."
    }
}
$factoryHash = Get-LzReleaseHash $FactoryCiReport
$e2eHash = Get-LzReleaseHash $E2eReport
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

$factoryCompleted = ConvertTo-LzReleaseUtcInstant "$($factory.generatedAt)"
$e2eCompleted = ConvertTo-LzReleaseUtcInstant "$($e2e.completedAt)"
$attestedAt = ConvertTo-LzReleaseUtcInstant "$($attestation.issuedAt)"
$factoryAge = ($now - $factoryCompleted).TotalHours
$e2eAge = ($now - $e2eCompleted).TotalHours
$attestationAge = ($now - $attestedAt).TotalHours
$factoryFresh = $factoryAge -ge 0 -and $factoryAge -le $maximumAgeHours
$e2eFresh = $e2eAge -ge 0 -and $e2eAge -le $maximumAgeHours
$attestationFresh = $attestationAge -ge 0 -and $attestationAge -le $maximumAgeHours

Add-LzReleaseFinding 'R01' 'Factory CI report targets the current factory version.' `
    ("$($factory.factoryVersion)" -eq "$($factoryVersion.factoryVersion)") "$($factory.factoryVersion)"
# The skipped block is read defensively: a Factory CI report missing or
# malforming it is treated as if the checks were skipped, so the finding fails
# instead of the runner throwing under StrictMode.
$factorySkipped = Get-LzReleaseProperty $factory 'skipped'
$factoryTerraformSkipped = [bool](Get-LzReleaseProperty $factorySkipped 'terraform' $true)
$factoryStaticSkipped = [bool](Get-LzReleaseProperty $factorySkipped 'staticAnalysis' $true)
Add-LzReleaseFinding 'R02' 'Factory CI completed successfully without skipped checks.' `
    ([bool](Get-LzReleaseProperty $factory 'success' $false) -and -not $factoryTerraformSkipped -and -not $factoryStaticSkipped) `
    "success=$(Get-LzReleaseProperty $factory 'success' $false); terraformSkipped=$factoryTerraformSkipped; staticSkipped=$factoryStaticSkipped"
Add-LzReleaseFinding 'R03' 'Factory CI evidence is within the allowed age.' $factoryFresh `
    "completed=$($factoryCompleted.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R04' 'E2E generation report targets this repository and current factory version.' `
    ("$($e2e.repository)" -eq $expectedRepository -and
     "$($e2e.factoryVersion)" -eq "$($factoryVersion.factoryVersion)") `
    "repository=$($e2e.repository); version=$($e2e.factoryVersion)"
Add-LzReleaseFinding 'R05' 'E2E generation proof passed every gate: UI-driven config, zero residual placeholders, manifest match, init+validate, zero GUIDs.' `
    ([bool]$e2e.success -and [bool]$e2e.uiDriven -and
     [bool]$e2e.zeroResidualPlaceholders -and [bool]$e2e.manifestMatch -and
     [bool]$e2e.terraformInitValidatePassed -and [bool]$e2e.zeroGuids) `
    "success=$($e2e.success); uiDriven=$($e2e.uiDriven); placeholders=$($e2e.zeroResidualPlaceholders); manifest=$($e2e.manifestMatch); initValidate=$($e2e.terraformInitValidatePassed); guids=$($e2e.zeroGuids)"
Add-LzReleaseFinding 'R06' 'E2E generation evidence is within the allowed age.' $e2eFresh `
    "completed=$($e2eCompleted.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R07' 'Attestation identity and approval metadata are complete.' `
    ("$($attestation.repository)" -eq $expectedRepository -and
     "$($attestation.factoryVersion)" -eq "$($factoryVersion.factoryVersion)" -and
     -not [string]::IsNullOrWhiteSpace("$($attestation.reviewer)") -and
     -not [string]::IsNullOrWhiteSpace("$($attestation.approvalReference)")) `
    "reviewer=$($attestation.reviewer); approval=$($attestation.approvalReference)"
Add-LzReleaseFinding 'R08' 'Attestation is pinned to the exact input evidence.' `
    ("$($attestation.factoryCiReportSha256)" -eq $factoryHash -and
     "$($attestation.e2eReportSha256)" -eq $e2eHash) `
    "factory=$factoryHash; e2e=$e2eHash"
Add-LzReleaseFinding 'R09' 'Attestation is within the allowed age.' $attestationFresh `
    "issued=$($attestedAt.ToString('o')); maxHours=$maximumAgeHours"
Add-LzReleaseFinding 'R10' 'Independent e2e-evidence and branch-protection read-back is approved.' `
    ([bool]$attestation.e2eEvidenceVerified -and [bool]$attestation.branchProtectionVerified) `
    "e2eEvidence=$($attestation.e2eEvidenceVerified); branchProtection=$($attestation.branchProtectionVerified)"

$schemaCheck = Get-LzReleaseCheck $factory 'Schema variable drift'
$networkCheck = Get-LzReleaseCheck $factory 'Site no network'
$gates = [ordered]@{
    schemaVariableDriftCheckPasses = (
        $schemaCheck.Count -eq 1 -and "$($schemaCheck[0].status)" -eq 'passed'
    )
    endToEndGenerationProofPasses = (
        [bool]$e2e.success -and [bool]$e2e.uiDriven -and
        [bool]$attestation.e2eEvidenceVerified
    )
    oidcTokenExchangeVerifiedLive = [bool]$attestation.oidcTokenExchangeVerifiedLive
    avmPinsVerifiedByInit = [bool]$attestation.avmPinsVerifiedByInit
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
        e2eReport = $E2eReport
        e2eSha256 = $e2eHash
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
