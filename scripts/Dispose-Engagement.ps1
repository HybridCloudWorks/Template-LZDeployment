#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 6 engagement disposal: archive the evidence, then delete the clone's
    residue and end the operator's sessions. Plan-first; nothing happens
    without -Apply.

.DESCRIPTION
    "Archive, then delete." Steps, in order:

      1. ARCHIVE to -ArchivePath: lz-config.json (the regeneration key -
         disposal HARD-FAILS if it cannot be archived and verified),
         bootstrap-plan.json / bootstrap-audit.json, scaffold-plan.json /
         scaffold-audit.json, discovery-inventory.json /
         tenant-readiness-report.md, render-manifest.json, .reports/** (the
         legacy bootstrap reports), and dogfood / release evidence
         (dogfood-report.json, dogfood-evidence/**, release-readiness*).
         Every archived copy is verified by SHA-256 hash against its source
         BEFORE anything is deleted.

      2. DELETE from the clone: .lz-bootloader-state.json, generated-output/,
         the rendered staging output (LZ_RENDERED_PATH, default
         ./rendered-output), every .terraform/ cache, and *.lz-backup-* dirs.

      3. END SESSIONS: az logout + az account clear, gh auth logout,
         terraform logout (drops the HCP Terraform credential), and removal of
         TFE_TOKEN and LZ_* variables from the current process. Shell-profile
         cleanup commands are PRINTED for the operator to apply; profiles are
         never edited by this script.

      4. Print the MUST NOT DELETE list - the state storage account and
         containers (or HCP Terraform workspaces), the landing-zone identities
         in the client tenant, the customer repository, and the archive just
         written ARE the deliverable - plus the fork-residue reminder (the
         factory fork retains AZURE_* secrets, TF_API_TOKEN, environments, and
         bootstrap branches) with the gh commands to clean them.

    Fork cleanup is only EXECUTED with an explicit -IncludeForkCleanup
    combined with -Apply and a -ForkRepository; otherwise the commands are
    printed for manual review.

.PARAMETER ArchivePath
    Destination directory for the evidence archive. Required. Created if
    missing. Also receives disposal-plan.json / disposal-audit.json.

.PARAMETER EngagementRoot
    Root of the engagement clone to dispose. Default: current directory.

.PARAMETER ForkRepository
    The factory fork as <owner>/<name>. Required when -IncludeForkCleanup is
    given; otherwise used only to render the printed cleanup commands.

.PARAMETER Apply
    Perform the archive, deletions, and session logout. Without it the script
    prints and records the full plan and changes nothing except writing
    disposal-plan.json to -ArchivePath.

.PARAMETER IncludeForkCleanup
    Execute the fork-residue cleanup (delete AZURE_*/TF_* secrets and
    variables, factory environments, and bootstrap/* branches on
    -ForkRepository). Requires -Apply. Off by default because the fork may be
    shared across engagements.

.EXAMPLE
    ./scripts/Dispose-Engagement.ps1 -ArchivePath D:\clients\contoso\lz-archive

    Plan only: shows what would be archived, deleted, and logged out.

.EXAMPLE
    ./scripts/Dispose-Engagement.ps1 -ArchivePath D:\clients\contoso\lz-archive -Apply

    Archives (hash-verified), deletes the clone residue, ends sessions, and
    prints the fork-residue commands without running them.

.NOTES
    Exit code 0 on success; 1 on failure (the audit records the failing step).
    Deletion NEVER starts unless every archive copy verified and lz-config.json
    is among them.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [string]$EngagementRoot = '.',
    [string]$ForkRepository = '',
    [switch]$Apply,
    [switch]$IncludeForkCleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-LzDisposalEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

function Invoke-LzDisposalCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [switch]$AllowFailure
    )
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-LzDisposalEvent WARN "'$Command' not found on PATH; skipped: $Command $($Arguments -join ' ')"
        return $null
    }
    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-LzDisposalEvent WARN "$Command $($Arguments -join ' ') exited $LASTEXITCODE (continuing)."
            return $null
        }
        throw "$Command failed: $($output -join ' ')"
    }
    return $output
}

if ($IncludeForkCleanup -and -not $Apply) {
    Write-LzDisposalEvent FAIL '-IncludeForkCleanup requires -Apply. Fork cleanup is never executed from a plan run.'
    exit 1
}
if ($IncludeForkCleanup -and -not $ForkRepository) {
    Write-LzDisposalEvent FAIL '-IncludeForkCleanup requires -ForkRepository <owner>/<name>.'
    exit 1
}

if (-not (Test-Path $EngagementRoot -PathType Container)) {
    Write-LzDisposalEvent FAIL "Engagement root not found: $EngagementRoot"
    exit 1
}
$root = (Resolve-Path $EngagementRoot).Path
New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
$archiveRoot = (Resolve-Path $ArchivePath).Path
$mode = if ($Apply) { 'apply' } else { 'plan' }
Write-LzDisposalEvent INFO "Disposal mode: $mode. Engagement root: $root"
Write-LzDisposalEvent INFO "Archive destination: $archiveRoot"

# -- Step 1 candidates: evidence to archive ----------------------------------
$evidenceNames = @(
    'lz-config.json'
    'bootstrap-plan.json'
    'bootstrap-audit.json'
    'scaffold-plan.json'
    'scaffold-audit.json'
    'discovery-inventory.json'
    'tenant-readiness-report.md'
    'render-manifest.json'
    'dogfood-report.json'
)
$evidenceDirectories = @('.reports', 'dogfood-evidence')
$evidencePatterns = @('release-readiness*')

# Separator-anchored containment: a raw prefix test would treat 'factory-notes'
# as inside 'factory' and 'D:\archive2' as inside 'D:\arch'.
function Test-LzPathWithin {
    param([string]$Path, [string]$Container)
    $trimmed = $Container.TrimEnd('\', '/')
    if ($Path.Equals($trimmed, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $Path.StartsWith($trimmed + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

# The archive must never recurse into itself, git internals, provider caches,
# or the factory's own test fixtures (which contain sample evidence files).
$excludePrefixes = @(
    (Join-Path $root '.git')
    (Join-Path $root 'node_modules')
    (Join-Path $root 'factory')
    $archiveRoot
)
function Test-LzExcludedPath {
    param([string]$Path)
    foreach ($prefix in $excludePrefixes) {
        if (Test-LzPathWithin -Path $Path -Container $prefix) { return $true }
    }
    if ($Path -match '[\\/]\.terraform[\\/]') { return $true }
    return $false
}

$archiveSet = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
function Add-LzArchiveCandidate {
    param([System.IO.FileInfo]$File)
    if (Test-LzExcludedPath -Path $File.FullName) { return }
    if (-not $seen.Add($File.FullName)) { return }
    $relative = $File.FullName.Substring($root.Length).TrimStart('\', '/')
    $archiveSet.Add([pscustomobject]@{
            source      = $File.FullName
            relative    = $relative
            destination = Join-Path $archiveRoot $relative
        })
}

foreach ($file in @(Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $evidenceNames })) {
    Add-LzArchiveCandidate -File $file
}
foreach ($directory in $evidenceDirectories) {
    $directoryPath = Join-Path $root $directory
    if (Test-Path $directoryPath -PathType Container) {
        foreach ($file in @(Get-ChildItem -Path $directoryPath -Recurse -File -Force)) {
            Add-LzArchiveCandidate -File $file
        }
    }
}
foreach ($pattern in $evidencePatterns) {
    foreach ($file in @(Get-ChildItem -Path $root -Recurse -File -Force -Filter $pattern -ErrorAction SilentlyContinue)) {
        Add-LzArchiveCandidate -File $file
    }
}

$hasRegenerationKey = [bool]($archiveSet | Where-Object { $_.relative -match '(^|[\\/])lz-config\.json$' })

# -- Step 2 candidates: clone residue to delete ------------------------------
$deleteSet = [System.Collections.Generic.List[string]]::new()
$stateFile = Join-Path $root '.lz-bootloader-state.json'
if (Test-Path $stateFile) { $deleteSet.Add($stateFile) }
foreach ($residueDirectory in @('generated-output', 'rendered-output')) {
    $residuePath = Join-Path $root $residueDirectory
    if (Test-Path $residuePath) { $deleteSet.Add((Resolve-Path $residuePath).Path) }
}
if ($env:LZ_RENDERED_PATH -and (Test-Path $env:LZ_RENDERED_PATH)) {
    # Containment guard: this is the only delete candidate sourced from an
    # environment variable, so it must never escape the engagement root, name
    # the root itself, or reach into the just-verified archive.
    $resolvedRendered = (Resolve-Path $env:LZ_RENDERED_PATH).Path
    $strictlyInsideRoot = (Test-LzPathWithin -Path $resolvedRendered -Container $root) -and
        -not $resolvedRendered.TrimEnd('\', '/').Equals($root.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)
    $insideArchive = Test-LzPathWithin -Path $resolvedRendered -Container $archiveRoot
    if (-not $strictlyInsideRoot -or $insideArchive) {
        Write-LzDisposalEvent WARN "LZ_RENDERED_PATH ('$resolvedRendered') was NOT added to the delete set: delete candidates must be strictly inside the engagement root ('$root') and outside the archive ('$archiveRoot'). If that path is really this engagement's rendered staging output, delete it manually after reviewing it."
    }
    elseif (-not $deleteSet.Contains($resolvedRendered)) {
        $deleteSet.Add($resolvedRendered)
    }
}
foreach ($cache in @(Get-ChildItem -Path $root -Recurse -Directory -Force -Filter '.terraform' -ErrorAction SilentlyContinue)) {
    if (Test-LzPathWithin -Path $cache.FullName -Container $archiveRoot) { continue }
    if ($cache.FullName -match '[\\/]\.git[\\/]') { continue }
    $deleteSet.Add($cache.FullName)
}
foreach ($backup in @(Get-ChildItem -Path $root -Recurse -Directory -Force -Filter '*.lz-backup-*' -ErrorAction SilentlyContinue)) {
    if (Test-LzPathWithin -Path $backup.FullName -Container $archiveRoot) { continue }
    $deleteSet.Add($backup.FullName)
}

# -- Step 3 candidates: sessions and process variables ------------------------
$sessionCommands = @(
    'az logout'
    'az account clear'
    'gh auth logout --hostname github.com'
    'terraform logout'
)
$engagementVariables = @(Get-ChildItem Env: | Where-Object { $_.Name -eq 'TFE_TOKEN' -or $_.Name -like 'LZ_*' })

# -- Step 4 text: what must survive, and the fork residue --------------------
$mustNotDelete = @(
    'Terraform state storage account and containers (or the HCP Terraform workspaces) - the landing zone state lives there.'
    'Landing-zone identities in the client tenant (app registrations, service principals, federated credentials, role assignments) - they serve the deployed landing zone.'
    'The generated customer repository - it IS the deliverable.'
    "The archived evidence at $archiveRoot - the regeneration key and audit trail."
)
$forkDisplay = if ($ForkRepository) { $ForkRepository } else { '<owner>/<fork>' }
$forkCommands = @(
    "gh secret list --repo $forkDisplay"
    "gh secret delete <NAME> --repo $forkDisplay                # for each AZURE_* secret (and TF_API_TOKEN on pre-0.10.0 legacy estates)"
    "gh variable list --repo $forkDisplay"
    "gh variable delete <NAME> --repo $forkDisplay              # for each AZURE_*, FACTORY_VERSION variable (and TF_CLOUD_* on legacy estates)"
    "gh api repos/$forkDisplay/environments --jq '.environments[].name'"
    "gh api --method DELETE repos/$forkDisplay/environments/<name>"
    "gh api repos/$forkDisplay/branches --jq '.[].name'"
    "gh api --method DELETE repos/$forkDisplay/git/refs/heads/<bootstrap-branch>"
)

# -- Evidence: disposal plan --------------------------------------------------
$planRecord = [ordered]@{
    schemaVersion = '1.0.0'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    mode = $mode
    engagementRoot = $root
    archivePath = $archiveRoot
    regenerationKeyPresent = $hasRegenerationKey
    archive = @($archiveSet | Select-Object relative, source, destination)
    delete = @($deleteSet)
    sessionCommands = @($sessionCommands)
    processVariablesToClear = @($engagementVariables | ForEach-Object { $_.Name })
    forkCleanup = [ordered]@{
        execute = [bool]$IncludeForkCleanup
        repository = $ForkRepository
        commands = @($forkCommands)
    }
    mustNotDelete = @($mustNotDelete)
}
$planPath = Join-Path $archiveRoot 'disposal-plan.json'
$planRecord | ConvertTo-Json -Depth 20 | Set-Content $planPath -Encoding utf8

Write-LzDisposalEvent INFO "Archive candidates: $($archiveSet.Count) file(s); deletion candidates: $($deleteSet.Count) path(s)."
foreach ($item in $archiveSet) { Write-LzDisposalEvent INFO "  archive: $($item.relative)" }
foreach ($item in $deleteSet) { Write-LzDisposalEvent INFO "  delete:  $item" }
if (-not $Apply) {
    Write-LzDisposalEvent INFO 'Sessions that -Apply would end:'
    foreach ($command in $sessionCommands) { Write-LzDisposalEvent INFO "  $command" }
    foreach ($variable in $engagementVariables) { Write-LzDisposalEvent INFO "  clear process variable: $($variable.Name)" }
}

if (-not $hasRegenerationKey) {
    Write-LzDisposalEvent FAIL 'lz-config.json (the regeneration key for the entire landing zone) was not found under the engagement root. Disposal refuses to proceed - locate and archive it first.'
    Write-LzDisposalEvent OK "Plan: $planPath"
    exit 1
}

$audit = [ordered]@{
    schemaVersion = '1.0.0'
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    mode = $mode
    archived = @()
    deleted = @()
    sessions = @()
    forkCleanup = @()
    status = 'planned'
    error = $null
}
$auditPath = Join-Path $archiveRoot 'disposal-audit.json'

try {
    if ($Apply) {
        # -- 1. Archive, then verify every copy by hash. Nothing is deleted
        #      unless this whole block succeeds.
        Write-LzDisposalEvent INFO 'Step 1: archiving evidence (hash-verified).'
        foreach ($item in $archiveSet) {
            $destinationDirectory = Split-Path -Parent $item.destination
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            Copy-Item -Path $item.source -Destination $item.destination -Force
            $sourceHash = (Get-FileHash -Path $item.source -Algorithm SHA256).Hash
            $copyHash = (Get-FileHash -Path $item.destination -Algorithm SHA256).Hash
            if ($sourceHash -ne $copyHash) {
                throw "Archive verification failed for $($item.relative): source $sourceHash != copy $copyHash. Nothing has been deleted."
            }
            $audit.archived += [pscustomobject]@{ relative = $item.relative; sha256 = $copyHash }
            Write-LzDisposalEvent OK "  archived + verified: $($item.relative)"
        }
        $keyArchived = [bool]($audit.archived | Where-Object { $_.relative -match '(^|[\\/])lz-config\.json$' })
        if (-not $keyArchived) {
            throw 'lz-config.json was not archived. Disposal hard-fails before any deletion: it is the regeneration key.'
        }

        # -- 2. Delete clone residue.
        Write-LzDisposalEvent INFO 'Step 2: deleting clone residue.'
        foreach ($path in $deleteSet) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -Confirm:$false
                $audit.deleted += $path
                Write-LzDisposalEvent OK "  deleted: $path"
            }
        }

        # -- 3. End sessions and clear process variables.
        Write-LzDisposalEvent INFO 'Step 3: ending sessions.'
        $null = Invoke-LzDisposalCommand az @('logout') -AllowFailure
        $null = Invoke-LzDisposalCommand az @('account', 'clear') -AllowFailure
        $null = Invoke-LzDisposalCommand gh @('auth', 'logout', '--hostname', 'github.com') -AllowFailure
        $null = Invoke-LzDisposalCommand terraform @('logout') -AllowFailure
        $audit.sessions = @('az logout', 'az account clear', 'gh auth logout', 'terraform logout')
        foreach ($variable in $engagementVariables) {
            Remove-Item -Path "Env:$($variable.Name)" -ErrorAction SilentlyContinue
            Write-LzDisposalEvent OK "  cleared from this process: $($variable.Name)"
        }
    }

    # Profile cleanup is the operator's call: emit the commands, never edit
    # profiles silently.
    if (@($engagementVariables).Count) {
        Write-LzDisposalEvent WARN 'If any of these variables are set in your shell profile, remove them there too (this script does not edit profiles):'
        foreach ($variable in $engagementVariables) {
            Write-LzDisposalEvent INFO ("  PowerShell profile: remove any line like  `$env:{0} = '...'" -f $variable.Name)
            Write-LzDisposalEvent INFO ("  bash/zsh profile:   remove any line like  export {0}=..." -f $variable.Name)
        }
    }

    # -- 4a. Fork residue cleanup (explicitly gated).
    if ($Apply -and $IncludeForkCleanup) {
        Write-LzDisposalEvent INFO "Step 4: fork-residue cleanup on $ForkRepository."
        $secretNames = @(Invoke-LzDisposalCommand gh @('secret', 'list', '--repo', $ForkRepository, '--json', 'name', '--jq', '.[].name') -AllowFailure) |
            Where-Object { $_ -match '^AZURE_' -or $_ -eq 'TF_API_TOKEN' }
        foreach ($name in $secretNames) {
            $null = Invoke-LzDisposalCommand gh @('secret', 'delete', $name, '--repo', $ForkRepository) -AllowFailure
            $audit.forkCleanup += "secret:$name"
            Write-LzDisposalEvent OK "  deleted fork secret: $name"
        }
        $variableNames = @(Invoke-LzDisposalCommand gh @('variable', 'list', '--repo', $ForkRepository, '--json', 'name', '--jq', '.[].name') -AllowFailure) |
            Where-Object { $_ -match '^AZURE_|^TF_CLOUD_' -or $_ -eq 'FACTORY_VERSION' }
        foreach ($name in $variableNames) {
            $null = Invoke-LzDisposalCommand gh @('variable', 'delete', $name, '--repo', $ForkRepository) -AllowFailure
            $audit.forkCleanup += "variable:$name"
            Write-LzDisposalEvent OK "  deleted fork variable: $name"
        }
        $branchNames = @(Invoke-LzDisposalCommand gh @('api', "repos/$ForkRepository/branches", '--jq', '.[].name') -AllowFailure) |
            Where-Object { $_ -like 'bootstrap*' }
        foreach ($name in $branchNames) {
            $null = Invoke-LzDisposalCommand gh @('api', '--method', 'DELETE', "repos/$ForkRepository/git/refs/heads/$name") -AllowFailure
            $audit.forkCleanup += "branch:$name"
            Write-LzDisposalEvent OK "  deleted fork branch: $name"
        }
        Write-LzDisposalEvent WARN 'Fork environments were NOT deleted automatically (names vary per engagement). Review and delete them:'
        Write-LzDisposalEvent INFO "  gh api repos/$ForkRepository/environments --jq '.environments[].name'"
        Write-LzDisposalEvent INFO "  gh api --method DELETE repos/$ForkRepository/environments/<name>"
    }

    $audit.status = if ($Apply) { 'completed' } else { 'planned' }
}
catch {
    $audit.status = 'failed'
    $audit.error = $_.Exception.Message
    Write-LzDisposalEvent FAIL $_.Exception.Message
    exit 1
}
finally {
    $audit.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $audit | ConvertTo-Json -Depth 20 | Set-Content $auditPath -Encoding utf8

    Write-LzDisposalEvent INFO ('=' * 72)
    Write-LzDisposalEvent WARN 'MUST NOT DELETE - these ARE the deliverable:'
    foreach ($line in $mustNotDelete) { Write-LzDisposalEvent WARN "  * $line" }
    Write-LzDisposalEvent INFO ('=' * 72)
    Write-LzDisposalEvent WARN 'Fork residue reminder: the factory fork still holds AZURE_* secrets, TF_API_TOKEN, environments, and bootstrap branches.'
    if (-not ($Apply -and $IncludeForkCleanup)) {
        Write-LzDisposalEvent WARN 'To clean them (or re-run this script with -IncludeForkCleanup -ForkRepository <owner>/<name> -Apply):'
        foreach ($command in $forkCommands) { Write-LzDisposalEvent INFO "  $command" }
    }
    Write-LzDisposalEvent OK "Plan:  $planPath"
    Write-LzDisposalEvent OK "Audit: $auditPath"
}
exit 0
