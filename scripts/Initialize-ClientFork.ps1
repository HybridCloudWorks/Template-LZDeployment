#Requires -Version 7.0

<#
.SYNOPSIS
    Obtains a client's PRIVATE copy of the factory repository: creates the
    repo and mirror-pushes the source into it (-CreatePrivateCopy), or
    verifies an existing copy's visibility.

.DESCRIPTION
    Given -Repository <owner>/<name>, this script:

      1. (optional, -CreatePrivateCopy) creates a PRIVATE repository and
         mirror-pushes -SourceRepository into it. A GitHub fork of a public
         repository is always public, and the legacy bootstrap has
         historically committed `.lz-bootloader-state.json` (tenant and
         subscription IDs) to a bootstrap PR branch -- a private copy is the
         safe per-client mechanic when the copy exists on GitHub at all
         (decision 0001; a plain local clone is preferred, decision 0004).
      2. Reads the repository visibility back via the GitHub API and prints
         a verification table.

    That is ALL it does. The hardening stages this script used to carry --
    Actions enablement, branch protection with required checks and
    approvals, secret-scanning / push-protection configuration, and their
    API read-backs -- were RETIRED on 2026-08-07 (decision 0007,
    docs/decisions/0007-retire-client-copy-hardening.md). Under decision
    0004 the factory copy is a disposable installer that is never hardened;
    the surviving GENERATED repository is hardened by the broker
    (factory/bootstrap/LZFactory.Bootstrap.psm1: branch protection,
    required checks, environments, secrets, API read-back).

    Plan-first: without -Apply the script only reads current state and
    prints what would change (matching the broker / scaffold convention).
    The mutations are idempotent, so re-running is safe.

    Authentication comes exclusively from the operator's existing `gh auth
    login` session; no token is ever read, stored, or written by this script.

.PARAMETER Repository
    Target repository as <owner>/<name>. This is the client copy being
    created or verified, NOT the upstream factory.

.PARAMETER SourceRepository
    Source repository as <owner>/<name> to mirror when -CreatePrivateCopy is
    supplied. Ignored otherwise.

.PARAMETER CreatePrivateCopy
    Create -Repository as a new PRIVATE repository and mirror-push
    -SourceRepository into it, instead of assuming the copy already exists.

.PARAMETER Apply
    Perform the mutations. Without it the script is read-only and prints the
    plan.

.EXAMPLE
    ./scripts/Initialize-ClientFork.ps1 -Repository clientorg/lz-factory

    Plan only: reports whether clientorg/lz-factory exists and its
    visibility, and warns if it is public.

.EXAMPLE
    ./scripts/Initialize-ClientFork.ps1 -Repository clientorg/lz-factory `
        -SourceRepository HybridCloudWorks/Template-LZDeployment `
        -CreatePrivateCopy -Apply

    Creates the private copy, mirror-pushes the factory into it, and prints
    the visibility read-back.

.NOTES
    Requires: gh >= 2.x authenticated with permission to create repositories
    under the target owner. git is required only for -CreatePrivateCopy.

    Do NOT use this script to harden any repository. The factory copy is
    never hardened (decision 0004); the generated repository is hardened by
    the broker (decision 0007 records the retirement of this script's
    hardening stages).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[\w.-]+$')]
    [string]$Repository,

    [ValidatePattern('^$|^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[\w.-]+$')]
    [string]$SourceRepository = '',

    [switch]$CreatePrivateCopy,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PlannedActions = [System.Collections.Generic.List[string]]::new()
$script:VerificationRows = [System.Collections.Generic.List[object]]::new()

function Write-LzSection {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=== {0} ===' -f $Title)
}

function Add-LzPlannedAction {
    param([Parameter(Mandatory)][string]$Description)
    $script:PlannedActions.Add($Description)
    Write-Host ('  PLAN  {0}' -f $Description)
}

function Add-LzVerificationRow {
    param(
        [Parameter(Mandatory)][string]$Setting,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Actual
    )
    $status = if ($Expected -eq '(report only)') { 'INFO' }
    elseif ($Actual -eq $Expected) { 'OK' }
    else { 'MISMATCH' }
    $script:VerificationRows.Add([pscustomobject]@{
            Setting  = $Setting
            Expected = $Expected
            Actual   = $Actual
            Status   = $status
        })
}

function Invoke-LzGhApi {
    <#
    .SYNOPSIS
        Invokes `gh api` and returns parsed JSON, or $null on a 404 when
        -AllowNotFound is set. Never echoes tokens; gh supplies auth itself.
    #>
    param(
        [Parameter(Mandatory)][string[]]$ApiArguments,
        [switch]$AllowNotFound
    )
    $raw = & gh api @ApiArguments 2>&1
    $exit = $LASTEXITCODE
    $text = ($raw | ForEach-Object { "$_" }) -join "`n"
    if ($exit -ne 0) {
        if ($AllowNotFound -and $text -match 'HTTP 404|Not Found') { return $null }
        throw "gh api $($ApiArguments -join ' ') failed (exit $exit): $text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 30
}

function Get-LzJsonProperty {
    <#
    .SYNOPSIS
        StrictMode-safe property access on a ConvertFrom-Json object graph.
    #>
    param(
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

# --- Preflight ---------------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'The GitHub CLI (gh) is required and was not found on PATH.'
}
if ($CreatePrivateCopy) {
    if (-not $SourceRepository) {
        throw '-CreatePrivateCopy requires -SourceRepository <owner>/<name>.'
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is required for -CreatePrivateCopy and was not found on PATH.'
    }
}

$mode = if ($Apply) { 'APPLY' } else { 'PLAN (read-only; supply -Apply to mutate)' }
Write-Host ('Initialize-ClientFork: {0} -- mode: {1}' -f $Repository, $mode)

# --- Step 1: repository existence / private copy -----------------------------
Write-LzSection 'Repository'
$repoInfo = Invoke-LzGhApi -ApiArguments @("repos/$Repository") -AllowNotFound

if ($null -eq $repoInfo) {
    if (-not $CreatePrivateCopy) {
        throw "Repository $Repository does not exist (or is not visible to this gh session). Supply -CreatePrivateCopy -SourceRepository <owner>/<name> to create it."
    }
    if ($Apply) {
        Write-Host ('  Creating PRIVATE repository {0} ...' -f $Repository)
        & gh repo create $Repository --private --description 'Landing Zone factory (client instance)' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "gh repo create $Repository failed (exit $LASTEXITCODE)." }

        $mirrorPath = Join-Path ([System.IO.Path]::GetTempPath()) ("lz-fork-mirror-{0}" -f [guid]::NewGuid())
        try {
            Write-Host ('  Mirroring {0} -> {1} ...' -f $SourceRepository, $Repository)
            # GitHub's documented repository-duplication procedure: clone
            # --bare, then push --mirror. A --mirror clone would also fetch
            # GitHub's read-only refs/pull/* refs, and the push would then be
            # rejected on those hidden refs (non-zero exit) even after every
            # branch and tag transferred successfully.
            # Auth is delegated to gh's git credential helper for both clone
            # and push; no token is materialized by this script.
            & git -c credential.helper='!gh auth git-credential' clone --bare "https://github.com/$SourceRepository.git" $mirrorPath | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "git clone --bare of $SourceRepository failed (exit $LASTEXITCODE). NOT RUN because of this failure: mirror push -- $Repository is an EMPTY repository. Fix the clone failure and re-run with -Apply (idempotent)."
            }
            & git -C $mirrorPath -c credential.helper='!gh auth git-credential' push --mirror "https://github.com/$Repository.git" | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "git push --mirror to $Repository failed (exit $LASTEXITCODE). $Repository may hold partial content. Fix the push failure and re-run with -Apply (idempotent)."
            }
        }
        finally {
            if (Test-Path $mirrorPath) { Remove-Item $mirrorPath -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $repoInfo = Invoke-LzGhApi -ApiArguments @("repos/$Repository")

        # A mirror copies every ref. Legacy bootstrap branches may carry
        # .lz-bootloader-state.json (tenant/subscription IDs) -- surface them.
        $branches = Invoke-LzGhApi -ApiArguments @("repos/$Repository/branches?per_page=100") -AllowNotFound
        $residue = @($branches | Where-Object { (Get-LzJsonProperty $_ 'name' '') -like 'bootstrap/*' })
        if ($residue.Count -gt 0) {
            Write-Warning ('Mirrored bootstrap branches detected (may contain .lz-bootloader-state.json): {0}. Review and delete them from {1}.' -f (($residue | ForEach-Object { $_.name }) -join ', '), $Repository)
        }
    }
    else {
        Add-LzPlannedAction ("Create PRIVATE repository $Repository (gh repo create --private) and mirror-push $SourceRepository into it")
        Add-LzPlannedAction 'After mirroring: review mirrored bootstrap/* branches for .lz-bootloader-state.json residue'
    }
}
else {
    $visibility = [string](Get-LzJsonProperty $repoInfo 'visibility' 'unknown')
    Write-Host ('  Exists: {0} (visibility: {1})' -f $Repository, $visibility)
    if ($visibility -ne 'private') {
        Write-Warning ('{0} is {1}. A fork of a public repository is always public, and the legacy bootstrap has committed .lz-bootloader-state.json (tenant/subscription IDs) to bootstrap PRs. Prefer -CreatePrivateCopy for client instances.' -f $Repository, $visibility)
    }
    if ($CreatePrivateCopy) {
        Write-Host '  -CreatePrivateCopy requested but the repository already exists; skipping creation (idempotent).'
    }
}

# --- Step 2: read-back verification ------------------------------------------
# Hardening stages retired 2026-08-07 (decision 0007): the factory copy is
# disposable and never hardened (decision 0004); the broker hardens the
# generated repository. Only the visibility read-back remains -- it is the
# private-copy mechanic's own guarantee.
Write-LzSection 'Verification (API read-back)'
if ($null -eq $repoInfo -and -not $Apply) {
    Write-Host '  Repository does not exist yet -- verification will run after -Apply.'
}
else {
    $verifyRepo = Invoke-LzGhApi -ApiArguments @("repos/$Repository")
    $expectedVisibility = if ($CreatePrivateCopy) { 'private' } else { '(report only)' }
    Add-LzVerificationRow -Setting 'repository.visibility' -Expected $expectedVisibility -Actual ([string](Get-LzJsonProperty $verifyRepo 'visibility' 'unknown'))
    $script:VerificationRows | Format-Table -AutoSize | Out-String | Write-Host
}

# --- Summary / exit code -----------------------------------------------------
Write-LzSection 'Summary'
if (-not $Apply) {
    if ($script:PlannedActions.Count -eq 0) {
        Write-Host '  Plan: no changes required -- target already matches the desired configuration.'
    }
    else {
        Write-Host ('  Plan: {0} change(s) pending. Re-run with -Apply to make them.' -f $script:PlannedActions.Count)
    }
    exit 0
}

$mismatches = @($script:VerificationRows | Where-Object Status -eq 'MISMATCH')
if ($mismatches.Count -gt 0) {
    # Write-Host, not Write-Error: with $ErrorActionPreference = 'Stop' a
    # Write-Error would throw and make the exit 1 unreachable.
    Write-Host ('  ERROR: Apply completed but {0} verification row(s) MISMATCH -- the read-back does not match the requested configuration. Review the table above.' -f $mismatches.Count)
    exit 1
}
Write-Host '  Apply complete: every read-back matches the requested configuration.'
exit 0
