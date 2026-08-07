#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 1 fork-init: configures a client-owned copy of the factory repository
    with the GitHub settings that forks and copies do NOT inherit.

.DESCRIPTION
    Forks and repository copies do not inherit: Actions enablement, branch
    protection / rulesets, secrets, variables, environments, or third-party
    integrations. In addition, `main` historically carried NO
    required_status_checks, so every check in this repo was advisory.

    Given -Repository <owner>/<name>, this script:

      1. (optional, -CreatePrivateCopy) creates a PRIVATE repository and
         mirror-pushes the source into it. A GitHub fork of a public
         repository is always public, and the legacy bootstrap has
         historically committed `.lz-bootloader-state.json` (tenant and
         subscription IDs) to a bootstrap PR branch -- a private copy is the
         safe per-client mechanic.
      2. Enables GitHub Actions on the target repository.
      3. Configures classic branch protection on the default branch with
         required status checks (stable job-level check names this repo's
         workflows produce), strict up-to-date enforcement, and required PR
         approvals (>= 1).
      4. Reads the secret-scanning / push-protection state and (with -Apply)
         attempts to enable both.
      5. Reads EVERY setting back via the GitHub API after configuring and
         prints a verification table.

    Plan-first: without -Apply the script only reads current state and prints
    what would change (matching the broker / scaffold convention). All
    mutations are idempotent PUT/PATCH calls, so re-running is safe.

    Authentication comes exclusively from the operator's existing `gh auth
    login` session; no token is ever read, stored, or written by this script.

.PARAMETER Repository
    Target repository as <owner>/<name>. This is the client fork / copy being
    initialized, NOT the CBTS upstream.

.PARAMETER SourceRepository
    Source repository as <owner>/<name> to mirror when -CreatePrivateCopy is
    supplied. Ignored otherwise.

.PARAMETER CreatePrivateCopy
    Create -Repository as a new PRIVATE repository and mirror-push
    -SourceRepository into it, instead of assuming a fork already exists.

.PARAMETER Branch
    Branch to protect. Defaults to main.

.PARAMETER RequiredApprovals
    Required approving review count for pull requests. Minimum 1.

.PARAMETER RequiredChecks
    Status check contexts to require on the protected branch. GitHub matches
    these against CHECK-RUN NAMES, which for GitHub Actions are the job-level
    `name:` values (verified against this repo's check-runs API: the Factory
    CI check reports as "Factory CI", not "Factory CI / Factory CI").

    Defaults to the stable check names this repository's workflows produce:
      - "Factory CI"                  (factory-ci.yml,          job: factory-ci)
      - "Enforce Immutable Action Refs" (action-pinning-policy.yml, job: enforce-pinning)
      - "TruffleHog Secret Scan"      (secrets-scan.yml, job: trufflehog-scan)
      - "Gitleaks Secret Detection"   (secrets-scan.yml, job: gitleaks-scan)
      - "Terraform Security Scan"     (secrets-scan.yml, job: terraform-security-scan)

    CAVEAT: "Factory CI" and "Enforce Immutable Action Refs" run behind
    `paths:` filters. A PR that touches none of their paths never reports the
    check, and with it required the PR waits on "Expected" forever. The
    secrets-scan checks have no path filter and always report. Narrow this
    list (or remove the path filters in the fork) if that trade-off is wrong
    for the engagement.

.PARAMETER EnforceAdmins
    Also apply the protection rules to repository administrators.

.PARAMETER Apply
    Perform the mutations. Without it the script is read-only and prints the
    plan.

.EXAMPLE
    ./scripts/Initialize-ClientFork.ps1 -Repository clientorg/lz-factory

    Plan only: shows current state of clientorg/lz-factory and every change
    that -Apply would make.

.EXAMPLE
    ./scripts/Initialize-ClientFork.ps1 -Repository clientorg/lz-factory `
        -SourceRepository cbts/HCW-Plan_LZDeployment -CreatePrivateCopy -Apply

    Creates the private copy, mirror-pushes the factory into it, enables
    Actions, protects main, and prints the read-back verification table.

.NOTES
    Requires: gh >= 2.x authenticated with repository ADMINISTRATION on the
    target repository (branch protection and security_and_analysis writes are
    admin-only). git is required only for -CreatePrivateCopy.

    Enabling secret_scanning / push_protection on a PRIVATE repository
    requires GitHub Advanced Security licensing; the script reports (rather
    than fails) when GitHub rejects that PATCH.

    Wrong-target for client copies under decision 0004 (client copies are
    disposable and never hardened); applies to the upstream factory repo only.
    Disposition of this script is tracked in REVIEW.md section 12.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[\w.-]+$')]
    [string]$Repository,

    [ValidatePattern('^$|^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[\w.-]+$')]
    [string]$SourceRepository = '',

    [switch]$CreatePrivateCopy,

    [string]$Branch = 'main',

    [ValidateRange(1, 6)]
    [int]$RequiredApprovals = 1,

    [string[]]$RequiredChecks = @(
        'Factory CI',
        'Enforce Immutable Action Refs',
        'TruffleHog Secret Scan',
        'Gitleaks Secret Detection',
        'Terraform Security Scan'
    ),

    [switch]$EnforceAdmins,

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
        & gh repo create $Repository --private --description 'CBTS Landing Zone factory (client instance)' | Out-Host
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
                throw "git clone --bare of $SourceRepository failed (exit $LASTEXITCODE). NOT RUN because of this failure: mirror push, Actions enablement, branch protection, secret-scanning configuration -- $Repository is an EMPTY, UNHARDENED repository. Fix the clone failure and re-run with -Apply (idempotent)."
            }
            & git -C $mirrorPath -c credential.helper='!gh auth git-credential' push --mirror "https://github.com/$Repository.git" | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "git push --mirror to $Repository failed (exit $LASTEXITCODE). NOT RUN because of this failure: Actions enablement, branch protection, secret-scanning configuration -- $Repository may hold partial content and is UNHARDENED. Fix the push failure and re-run with -Apply (idempotent)."
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

# --- Step 2: Actions enablement ----------------------------------------------
Write-LzSection 'GitHub Actions enablement'
$actionsPermissions = $null
if ($null -ne $repoInfo) {
    $actionsPermissions = Invoke-LzGhApi -ApiArguments @("repos/$Repository/actions/permissions") -AllowNotFound
}
$actionsEnabled = [bool](Get-LzJsonProperty $actionsPermissions 'enabled' $false)
Write-Host ('  Current: enabled = {0}' -f $actionsEnabled)

if (-not $actionsEnabled) {
    if ($Apply) {
        Invoke-LzGhApi -ApiArguments @(
            '--method', 'PUT', "repos/$Repository/actions/permissions",
            '-F', 'enabled=true', '-f', 'allowed_actions=all'
        ) | Out-Null
        Write-Host '  Enabled Actions (allowed_actions=all; workflows are SHA-pinned by policy).'
    }
    else {
        Add-LzPlannedAction "Enable GitHub Actions on $Repository (PUT repos/$Repository/actions/permissions enabled=true)"
    }
}
else {
    Write-Host '  Actions already enabled; no change.'
}

# --- Step 3: branch protection with required status checks -------------------
Write-LzSection ("Branch protection on '$Branch'")
$protection = $null
if ($null -ne $repoInfo) {
    $protection = Invoke-LzGhApi -ApiArguments @("repos/$Repository/branches/$Branch/protection") -AllowNotFound
}

$currentContexts = @()
$currentApprovals = 0
$currentStrict = $false
$currentEnforceAdmins = $false
if ($null -ne $protection) {
    $rsc = Get-LzJsonProperty $protection 'required_status_checks'
    $currentContexts = @(Get-LzJsonProperty $rsc 'contexts' @())
    $currentStrict = [bool](Get-LzJsonProperty $rsc 'strict' $false)
    $reviews = Get-LzJsonProperty $protection 'required_pull_request_reviews'
    $currentApprovals = [int](Get-LzJsonProperty $reviews 'required_approving_review_count' 0)
    $enforceNode = Get-LzJsonProperty $protection 'enforce_admins'
    $currentEnforceAdmins = [bool](Get-LzJsonProperty $enforceNode 'enabled' $false)
    Write-Host ('  Current: contexts=[{0}] strict={1} approvals={2} enforce_admins={3}' -f ($currentContexts -join ', '), $currentStrict, $currentApprovals, $currentEnforceAdmins)
}
else {
    Write-Host '  Current: NO branch protection (all checks are advisory; merges prove nothing).'
}

$desiredContexts = @($RequiredChecks | Sort-Object -Unique)
$protectionInSync = ($null -ne $protection) -and
    $currentStrict -and
    ($currentApprovals -ge $RequiredApprovals) -and
    ($currentEnforceAdmins -eq [bool]$EnforceAdmins) -and
    (-not (Compare-Object -ReferenceObject $desiredContexts -DifferenceObject @($currentContexts | Sort-Object -Unique)))

$pathFiltered = @($RequiredChecks | Where-Object { $_ -in @('Factory CI', 'Enforce Immutable Action Refs') })
if ($pathFiltered.Count -gt 0) {
    Write-Warning ('Required check(s) [{0}] run behind paths: filters -- PRs that do not touch those paths will wait on "Expected" until the check list is narrowed or the filters are removed.' -f ($pathFiltered -join ', '))
}

if (-not $protectionInSync) {
    $protectionBody = [ordered]@{
        required_status_checks        = [ordered]@{
            strict   = $true
            contexts = $desiredContexts
        }
        enforce_admins                = [bool]$EnforceAdmins
        required_pull_request_reviews = [ordered]@{
            required_approving_review_count = $RequiredApprovals
            dismiss_stale_reviews           = $true
            require_code_owner_reviews      = $false
        }
        restrictions                  = $null
        allow_force_pushes            = $false
        allow_deletions               = $false
        required_conversation_resolution = $true
    }
    if ($Apply) {
        $temp = New-TemporaryFile
        try {
            $protectionBody | ConvertTo-Json -Depth 10 | Set-Content $temp -Encoding utf8
            Invoke-LzGhApi -ApiArguments @(
                '--method', 'PUT', "repos/$Repository/branches/$Branch/protection",
                '--input', $temp.FullName
            ) | Out-Null
        }
        finally {
            Remove-Item $temp -Force -ErrorAction SilentlyContinue
        }
        Write-Host ('  Applied protection: {0} required check(s), strict=true, approvals={1}, enforce_admins={2}.' -f $desiredContexts.Count, $RequiredApprovals, [bool]$EnforceAdmins)
    }
    else {
        Add-LzPlannedAction ("Set branch protection on $Repository@$Branch : required checks [{0}], strict=true, approvals>={1}, enforce_admins={2}, no force-push/deletion" -f ($desiredContexts -join ', '), $RequiredApprovals, [bool]$EnforceAdmins)
    }
}
else {
    Write-Host '  Protection already matches the desired configuration; no change.'
}

# --- Step 4: secret scanning / push protection -------------------------------
Write-LzSection 'Secret scanning & push protection'
$security = Get-LzJsonProperty $repoInfo 'security_and_analysis'
$secretScanStatus = [string](Get-LzJsonProperty (Get-LzJsonProperty $security 'secret_scanning') 'status' 'unknown')
$pushProtectStatus = [string](Get-LzJsonProperty (Get-LzJsonProperty $security 'secret_scanning_push_protection') 'status' 'unknown')
Write-Host ('  Current: secret_scanning={0} push_protection={1}' -f $secretScanStatus, $pushProtectStatus)

if ($secretScanStatus -ne 'enabled' -or $pushProtectStatus -ne 'enabled') {
    if ($Apply) {
        $securityBody = @{ security_and_analysis = @{
                secret_scanning                 = @{ status = 'enabled' }
                secret_scanning_push_protection = @{ status = 'enabled' }
            } }
        $temp = New-TemporaryFile
        try {
            $securityBody | ConvertTo-Json -Depth 6 | Set-Content $temp -Encoding utf8
            Invoke-LzGhApi -ApiArguments @(
                '--method', 'PATCH', "repos/$Repository", '--input', $temp.FullName
            ) | Out-Null
            Write-Host '  Enabled secret scanning and push protection.'
        }
        catch {
            # Private repos need GitHub Advanced Security licensing for this
            # PATCH; report instead of failing the whole fork-init.
            Write-Warning ('Could not enable secret scanning / push protection via API (likely Advanced Security licensing on a private repo): {0}. Enable it in Settings > Code security.' -f $_.Exception.Message)
        }
        finally {
            Remove-Item $temp -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Add-LzPlannedAction "Enable secret_scanning and secret_scanning_push_protection on $Repository (PATCH repos/$Repository; may require Advanced Security on private repos)"
    }
}
else {
    Write-Host '  Both already enabled; no change.'
}

# --- Step 5: read-back verification ------------------------------------------
Write-LzSection 'Verification (API read-back)'
if ($null -eq $repoInfo -and -not $Apply) {
    Write-Host '  Repository does not exist yet -- verification will run after -Apply.'
}
else {
    $verifyRepo = Invoke-LzGhApi -ApiArguments @("repos/$Repository")
    $verifyActions = Invoke-LzGhApi -ApiArguments @("repos/$Repository/actions/permissions") -AllowNotFound
    $verifyProtection = Invoke-LzGhApi -ApiArguments @("repos/$Repository/branches/$Branch/protection") -AllowNotFound

    $expectedVisibility = if ($CreatePrivateCopy) { 'private' } else { '(report only)' }
    Add-LzVerificationRow -Setting 'repository.visibility' -Expected $expectedVisibility -Actual ([string](Get-LzJsonProperty $verifyRepo 'visibility' 'unknown'))
    Add-LzVerificationRow -Setting 'actions.enabled' -Expected 'True' -Actual ([string]([bool](Get-LzJsonProperty $verifyActions 'enabled' $false)))

    if ($null -ne $verifyProtection) {
        $vRsc = Get-LzJsonProperty $verifyProtection 'required_status_checks'
        $vContexts = @(Get-LzJsonProperty $vRsc 'contexts' @()) | Sort-Object -Unique
        Add-LzVerificationRow -Setting 'protection.required_status_checks.contexts' -Expected ($desiredContexts -join '; ') -Actual ($vContexts -join '; ')
        Add-LzVerificationRow -Setting 'protection.required_status_checks.strict' -Expected 'True' -Actual ([string]([bool](Get-LzJsonProperty $vRsc 'strict' $false)))
        $vReviews = Get-LzJsonProperty $verifyProtection 'required_pull_request_reviews'
        Add-LzVerificationRow -Setting 'protection.required_approving_review_count' -Expected ([string]$RequiredApprovals) -Actual ([string][int](Get-LzJsonProperty $vReviews 'required_approving_review_count' 0))
        $vEnforce = Get-LzJsonProperty $verifyProtection 'enforce_admins'
        Add-LzVerificationRow -Setting 'protection.enforce_admins' -Expected ([string][bool]$EnforceAdmins) -Actual ([string]([bool](Get-LzJsonProperty $vEnforce 'enabled' $false)))
        $vForce = Get-LzJsonProperty $verifyProtection 'allow_force_pushes'
        Add-LzVerificationRow -Setting 'protection.allow_force_pushes' -Expected 'False' -Actual ([string]([bool](Get-LzJsonProperty $vForce 'enabled' $false)))
    }
    else {
        Add-LzVerificationRow -Setting 'protection (branch protection object)' -Expected 'configured' -Actual 'ABSENT'
    }

    $vSecurity = Get-LzJsonProperty $verifyRepo 'security_and_analysis'
    Add-LzVerificationRow -Setting 'security.secret_scanning' -Expected 'enabled' -Actual ([string](Get-LzJsonProperty (Get-LzJsonProperty $vSecurity 'secret_scanning') 'status' 'unknown'))
    Add-LzVerificationRow -Setting 'security.push_protection' -Expected 'enabled' -Actual ([string](Get-LzJsonProperty (Get-LzJsonProperty $vSecurity 'secret_scanning_push_protection') 'status' 'unknown'))

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
