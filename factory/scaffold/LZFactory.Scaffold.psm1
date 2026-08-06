#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-LzScaffoldEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

function Get-LzScaffoldEnv {
    param([string]$Name, [string]$Default = '')
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

function Get-LzScaffoldProperty {
    param([object]$Object, [string]$Name, $Default = $null)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Resolve-LzScaffoldPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}

function Test-LzScaffoldDescendant {
    param([string]$Parent, [string]$Child)
    $separator = [IO.Path]::DirectorySeparatorChar
    $parentFull = (Resolve-LzScaffoldPath $Parent).TrimEnd('\', '/') + $separator
    $childFull = Resolve-LzScaffoldPath $Child
    return $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-LzScaffoldCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [string]$WorkingDirectory,
        [switch]$AllowFailure
    )
    $oldLocation = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location $WorkingDirectory }
        $output = & $Command @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-Location $oldLocation
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Command failed with exit code $exitCode`: $($output -join ' ')"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | Where-Object { $null -ne $_ })
    }
}

function Get-LzScaffoldInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RenderedDirectory)

    $root = Resolve-LzScaffoldPath $RenderedDirectory
    $manifestPath = Join-Path $root 'render-manifest.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        throw "Renderer inventory not found: $manifestPath"
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 30
    if (-not $manifest.PSObject.Properties['files']) {
        throw 'render-manifest.json does not contain a files inventory.'
    }

    $expected = @($manifest.files | ForEach-Object {
        $destination = "$($_.Destination)" -replace '\\', '/'
        if ([string]::IsNullOrWhiteSpace($destination) -or
            [IO.Path]::IsPathRooted($destination) -or
            $destination -match '(^|/)\.\.(/|$)') {
            throw "Unsafe renderer destination: $destination"
        }
        $destination.TrimStart('/')
    })
    if (@($expected | Sort-Object -Unique).Count -ne $expected.Count) {
        throw 'render-manifest.json contains duplicate destination paths.'
    }

    $actual = @(Get-ChildItem $root -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
    } | Where-Object { $_ -ne 'render-manifest.json' } | Sort-Object)
    $expectedSorted = @($expected | Sort-Object)
    $missing = @($expectedSorted | Where-Object { $_ -notin $actual })
    $unexpected = @($actual | Where-Object { $_ -notin $expectedSorted })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw "Rendered inventory mismatch. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')"
    }

    $files = @($expectedSorted | ForEach-Object {
        $path = Join-Path $root $_
        [pscustomobject]@{
            path = $_
            sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = (Get-Item $path).Length
        }
    })
    $manifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject]@{
        manifest = $manifest
        manifestPath = $manifestPath
        manifestSha256 = $manifestHash
        files = $files
    }
}

function New-LzScaffoldPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Inventory,
        [Parameter(Mandatory)][string]$RenderedDirectory,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][bool]$CreateRepository,
        [Parameter(Mandatory)][bool]$Push
    )

    $repository = "$($Config.github.ownerName)/$($Config.github.repositoryName)"
    $defaultBranch = "$(Get-LzScaffoldProperty $Config.github 'defaultBranch' 'main')"
    [pscustomobject]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = 'plan'
        factoryVersion = "$($Inventory.manifest.factoryVersion)"
        configSchemaVersion = "$($Config.schemaVersion)"
        repository = $repository
        visibility = "$($Config.github.visibility)"
        defaultBranch = $defaultBranch
        renderedDirectory = Resolve-LzScaffoldPath $RenderedDirectory
        targetDirectory = Resolve-LzScaffoldPath $TargetDirectory
        manifestSha256 = $Inventory.manifestSha256
        fileCount = $Inventory.files.Count
        files = @($Inventory.files)
        createRepository = $CreateRepository
        push = $Push
        commitMessage = Get-LzScaffoldEnv 'LZ_SCAFFOLD_COMMIT_MESSAGE' "chore(factory): scaffold landing zone v$($Inventory.manifest.factoryVersion)"
        remoteUrl = Get-LzScaffoldEnv 'LZ_SCAFFOLD_REMOTE_URL' "https://github.com/$repository.git"
        publicationBranch = Get-LzScaffoldEnv 'LZ_SCAFFOLD_BRANCH' "agent/scaffold-$("$($Inventory.manifest.factoryVersion)" -replace '[^0-9A-Za-z._-]', '-')"
    }
}

function Copy-LzScaffoldTree {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$Inventory,
        [Parameter(Mandatory)][switch]$Force
    )

    $target = $Plan.targetDirectory
    $rendered = $Plan.renderedDirectory
    if ($target -eq $rendered -or
        (Test-LzScaffoldDescendant -Parent $rendered -Child $target) -or
        (Test-LzScaffoldDescendant -Parent $target -Child $rendered)) {
        throw 'Rendered and target directories must be separate and must not contain one another.'
    }

    $targetExists = Test-Path $target
    # @() must wrap the whole if-expression: a branch that emits an empty array
    # assigns $null, and $null.Count throws under Set-StrictMode Latest.
    $targetEntries = @(if ($targetExists) { Get-ChildItem $target -Force -ErrorAction SilentlyContinue })
    if ($targetEntries.Count -gt 0 -and -not $Force) {
        throw "Target directory is not empty: $target. Re-run with -Force only after reviewing scaffold-plan.json."
    }

    $parent = Split-Path -Parent $target
    if (-not $parent) { $parent = (Get-Location).Path }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $stage = Join-Path $parent ('.lz-scaffold-stage-' + [guid]::NewGuid().ToString('N'))
    $backup = $null
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($file in $Inventory.files) {
            $source = Join-Path $rendered $file.path
            $destination = Join-Path $stage $file.path
            $directory = Split-Path -Parent $destination
            if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
            Copy-Item $source $destination -Force
            $copiedHash = (Get-FileHash $destination -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($copiedHash -ne $file.sha256) {
                throw "Staged copy hash mismatch: $($file.path)"
            }
        }
        Copy-Item $Inventory.manifestPath (Join-Path $stage 'render-manifest.json') -Force

        if ($targetExists) {
            $gitDirectory = Join-Path $target '.git'
            if (Test-Path $gitDirectory) {
                Copy-Item $gitDirectory (Join-Path $stage '.git') -Recurse -Force
            }
            if ($targetEntries.Count -gt 0) {
                $backup = "$target.lz-backup-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
                Move-Item $target $backup
            }
            else {
                Remove-Item $target -Force
            }
        }
        Move-Item $stage $target
    }
    catch {
        if (-not (Test-Path $target) -and $backup -and (Test-Path $backup)) {
            Move-Item $backup $target
        }
        throw
    }
    finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    }
    return $backup
}

function Publish-LzScaffoldRepository {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$Config
    )
    foreach ($tool in @('git', 'gh')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required publication tool '$tool' is unavailable. See USER-CHECKLIST.md."
        }
    }
    $auth = Invoke-LzScaffoldCommand gh @('auth', 'status') -AllowFailure
    if ($auth.ExitCode -ne 0) { throw 'GitHub CLI is not authenticated. See USER-CHECKLIST.md.' }

    $repoView = Invoke-LzScaffoldCommand gh @('repo', 'view', $Plan.repository, '--json', 'nameWithOwner') -AllowFailure
    $repositoryExists = $repoView.ExitCode -eq 0
    if ($repoView.ExitCode -ne 0) {
        $repoError = ($repoView.Output -join ' ')
        if ($repoError -notmatch 'Could not resolve|Not Found|HTTP 404') {
            throw "Unable to inspect configured repository: $repoError"
        }
        if (-not $Plan.createRepository) {
            throw "Repository $($Plan.repository) does not exist and repository creation is disabled."
        }
        Invoke-LzScaffoldCommand gh @(
            'repo', 'create', $Plan.repository,
            "--$($Config.github.visibility)",
            '--description', "Azure landing zone generated for $($Config.organization.companyName)"
        ) | Out-Null
    }

    $gitDir = Join-Path $Plan.targetDirectory '.git'
    if ($repositoryExists -and -not (Test-Path $gitDir)) {
        throw "Repository $($Plan.repository) already exists. Use a clone of its default branch as LZ_SCAFFOLD_TARGET so history cannot be replaced."
    }
    if (-not (Test-Path $gitDir)) {
        Invoke-LzScaffoldCommand git @('init', '-b', $Plan.defaultBranch) $Plan.targetDirectory | Out-Null
    }
    $remote = Invoke-LzScaffoldCommand git @('remote', 'get-url', 'origin') $Plan.targetDirectory -AllowFailure
    if ($remote.ExitCode -ne 0) {
        Invoke-LzScaffoldCommand git @('remote', 'add', 'origin', $Plan.remoteUrl) $Plan.targetDirectory | Out-Null
    }
    elseif (($remote.Output -join '').Trim() -ne $Plan.remoteUrl) {
        throw "Existing origin does not match configured repository. Expected $($Plan.remoteUrl); got $(($remote.Output -join '').Trim())."
    }
    if ($repositoryExists) {
        $branch = Invoke-LzScaffoldCommand git @('branch', '--show-current') $Plan.targetDirectory
        if (($branch.Output -join '').Trim() -ne $Plan.defaultBranch) {
            throw "Existing target must have configured default branch '$($Plan.defaultBranch)' checked out before scaffold apply."
        }
    }

    Invoke-LzScaffoldCommand git @('add', '--all') $Plan.targetDirectory | Out-Null
    $changes = Invoke-LzScaffoldCommand git @('status', '--porcelain') $Plan.targetDirectory
    $hasChanges = $changes.Output.Count -gt 0
    if ($hasChanges) {
        Invoke-LzScaffoldCommand git @('commit', '-m', $Plan.commitMessage) $Plan.targetDirectory | Out-Null
    }
    $head = Invoke-LzScaffoldCommand git @('rev-parse', 'HEAD') $Plan.targetDirectory
    $headSha = (($head.Output -join '').Trim())
    $publishedBranch = $null
    $pullRequestUrl = $null
    if ($Plan.push -and ($hasChanges -or -not $repositoryExists)) {
        if ($repositoryExists) {
            $publishedBranch = $Plan.publicationBranch
            Invoke-LzScaffoldCommand git @('push', '--set-upstream', 'origin', "HEAD:$publishedBranch") $Plan.targetDirectory | Out-Null
            $existingPr = Invoke-LzScaffoldCommand gh @(
                'pr', 'view', $publishedBranch, '--repo', $Plan.repository, '--json', 'url', '--jq', '.url'
            ) $Plan.targetDirectory -AllowFailure
            if ($existingPr.ExitCode -eq 0) {
                $pullRequestUrl = (($existingPr.Output -join '').Trim())
            }
            else {
                $createdPr = Invoke-LzScaffoldCommand gh @(
                    'pr', 'create', '--repo', $Plan.repository, '--base', $Plan.defaultBranch,
                    '--head', $publishedBranch, '--draft', '--title', $Plan.commitMessage,
                    '--body', 'Generated by Landing Zone Factory Stage 10. Review scaffold-plan.json and scaffold-audit.json before merge.'
                ) $Plan.targetDirectory
                $pullRequestUrl = (($createdPr.Output -join "`n").Trim())
            }
        }
        else {
            $publishedBranch = $Plan.defaultBranch
            Invoke-LzScaffoldCommand git @('push', '--set-upstream', 'origin', "HEAD:$($Plan.defaultBranch)") $Plan.targetDirectory | Out-Null
        }
    }
    return [pscustomobject]@{
        commitSha = $headSha
        branch = $publishedBranch
        pullRequestUrl = $pullRequestUrl
        repositoryCreated = -not $repositoryExists
    }
}

function Test-LzScaffoldValidation {
    # Apply-time gate for the post-render validation stage: classifies the
    # validate-render.ps1 evidence for THIS render. 'missing' covers an absent
    # or unparseable report, 'stale' a report whose manifestSha256 does not
    # match the inventory just computed (evidence for a different render), and
    # 'fail'/'pass' mirror the report's own overallStatus. The caller decides
    # whether a non-pass status throws or is overridden.
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$ManifestSha256
    )
    $status = 'missing'
    $manifestMatch = $false
    if (Test-Path $ReportPath -PathType Leaf) {
        $report = $null
        try { $report = Get-Content $ReportPath -Raw | ConvertFrom-Json -Depth 30 }
        catch { $report = $null }
        if ($null -ne $report) {
            $manifestMatch = "$(Get-LzScaffoldProperty $report 'manifestSha256' '')" -eq $ManifestSha256
            if (-not $manifestMatch) { $status = 'stale' }
            elseif ("$(Get-LzScaffoldProperty $report 'overallStatus' '')" -eq 'pass') { $status = 'pass' }
            else { $status = 'fail' }
        }
    }
    return [pscustomobject]@{
        reportPath = $ReportPath
        status = $status
        manifestSha256Match = $manifestMatch
    }
}

function Invoke-LzScaffold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RenderedDirectory,
        [Parameter(Mandatory)][string]$TargetDirectory,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [switch]$Apply,
        [switch]$Force,
        [bool]$CreateRepository = $true,
        [bool]$Push = $true,
        [string]$ValidationReportPath = ''
    )

    if (-not (Test-Path $ConfigPath -PathType Leaf)) { throw "Config not found: $ConfigPath" }
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 50
    $inventory = Get-LzScaffoldInventory -RenderedDirectory $RenderedDirectory
    if ("$($inventory.manifest.schemaVersion)" -ne "$($config.schemaVersion)") {
        throw "Renderer/config schema mismatch: $($inventory.manifest.schemaVersion) != $($config.schemaVersion)"
    }
    if ("$($inventory.manifest.factoryVersion)" -ne "$($config.factoryVersion)") {
        throw "Renderer/config factory mismatch: $($inventory.manifest.factoryVersion) != $($config.factoryVersion)"
    }
    if ("$($inventory.manifest.company)" -ne "$($config.organization.companyName)") {
        throw "Renderer/config company mismatch: $($inventory.manifest.company) != $($config.organization.companyName)"
    }

    $plan = New-LzScaffoldPlan -Config $config -Inventory $inventory `
        -RenderedDirectory $RenderedDirectory -TargetDirectory $TargetDirectory `
        -CreateRepository $CreateRepository -Push $Push
    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
    $planPath = Join-Path $EvidenceDirectory 'scaffold-plan.json'
    $plan | ConvertTo-Json -Depth 30 | Set-Content $planPath -Encoding utf8

    $audit = [ordered]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = if ($Apply) { 'apply' } else { 'plan' }
        repository = $plan.repository
        manifestSha256 = $plan.manifestSha256
        fileCount = $plan.fileCount
        targetDirectory = $plan.targetDirectory
        applied = $false
        pushed = $false
        commitSha = $null
        branch = $null
        pullRequestUrl = $null
        repositoryCreated = $false
        backupDirectory = $null
        validation = $null
        pendingUserActivities = @()
        error = $null
    }

    if ($Apply) {
        try {
            # Post-render validation gate: apply refuses a render that has not
            # passed validate-render.ps1, or whose evidence describes another
            # render. Same fallback resolution as the validate entry point, so
            # a direct module call and the entry points agree on the location.
            if (-not $ValidationReportPath) {
                $ValidationReportPath = Join-Path (Get-LzScaffoldEnv 'LZ_VALIDATE_EVIDENCE' './validate-evidence') 'validate-report.json'
            }
            $validationCheck = Test-LzScaffoldValidation -ReportPath $ValidationReportPath -ManifestSha256 $inventory.manifestSha256
            $audit.validation = @{
                reportPath = $validationCheck.reportPath
                status = $validationCheck.status
                manifestSha256Match = $validationCheck.manifestSha256Match
                overridden = $false
            }
            if ($validationCheck.status -ne 'pass') {
                if ((Get-LzScaffoldEnv 'LZ_SCAFFOLD_ALLOW_UNVALIDATED' 'false') -eq 'true') {
                    $audit.validation.overridden = $true
                    Write-LzScaffoldEvent WARN "Post-render validation gate OVERRIDDEN (LZ_SCAFFOLD_ALLOW_UNVALIDATED=true): status '$($validationCheck.status)' for $ValidationReportPath. Publishing an unvalidated render requires a documented owner-approved exception; the override is recorded in scaffold-audit.json."
                }
                else {
                    $validationDetail = switch ($validationCheck.status) {
                        'stale' { "describes a different render (manifestSha256 mismatch against $($inventory.manifestSha256))" }
                        'fail' { 'does not record overallStatus pass - resolve every failing gate it lists' }
                        default { 'is missing or unreadable' }
                    }
                    throw "Post-render validation gate: report $ValidationReportPath $validationDetail. Run ./validate-render.ps1 against $($plan.renderedDirectory) and re-run the scaffold. Set LZ_SCAFFOLD_ALLOW_UNVALIDATED=true only with a documented owner-approved exception."
                }
            }
            $audit.backupDirectory = Copy-LzScaffoldTree -Plan $plan -Inventory $inventory -Force:$Force
            $audit.applied = $true
            $publication = Publish-LzScaffoldRepository -Plan $plan -Config $config
            $audit.commitSha = $publication.commitSha
            $audit.branch = $publication.branch
            $audit.pullRequestUrl = $publication.pullRequestUrl
            $audit.repositoryCreated = $publication.repositoryCreated
            $audit.pushed = $Push
            Write-LzScaffoldEvent OK "Scaffold applied to $($plan.targetDirectory)."
        }
        catch {
            $audit.error = $_.Exception.Message
            $audit.pendingUserActivities = @(
                'Review scaffold-audit.json, recover from backupDirectory when present, resolve the recorded error, and re-run the idempotent scaffold.'
            )
            $auditPath = Join-Path $EvidenceDirectory 'scaffold-audit.json'
            $audit | ConvertTo-Json -Depth 20 | Set-Content $auditPath -Encoding utf8
            throw
        }
    }
    else {
        $audit.pendingUserActivities = @(
            'Review scaffold-plan.json and set LZ_SCAFFOLD_APPLY=true to create/update and publish the target repository.'
            'Run ./validate-render.ps1 against the rendered tree before apply; apply refuses a missing, failed, or stale validate-report.json unless LZ_SCAFFOLD_ALLOW_UNVALIDATED=true is set with an approved exception.'
        )
        Write-LzScaffoldEvent OK "Plan complete: $planPath"
        Write-LzScaffoldEvent WARN 'No target or repository mutation was performed.'
    }

    $auditPath = Join-Path $EvidenceDirectory 'scaffold-audit.json'
    $audit | ConvertTo-Json -Depth 20 | Set-Content $auditPath -Encoding utf8
    return [pscustomobject]@{ Plan = $plan; Audit = [pscustomobject]$audit; PlanPath = $planPath; AuditPath = $auditPath }
}

Export-ModuleMember -Function @(
    'Get-LzScaffoldInventory'
    'New-LzScaffoldPlan'
    'Test-LzScaffoldValidation'
    'Invoke-LzScaffold'
)
