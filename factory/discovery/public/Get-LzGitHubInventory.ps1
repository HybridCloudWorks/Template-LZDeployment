#Requires -Version 7.0
<#
    GitHub discovery — read-only.

    Establishes what the bootstrap broker will actually be able to configure.
    The ownership model is the pivotal finding: a Free personal account cannot
    have environments or branch protection on a private repository, which
    silently removes every approval gate the deployment design depends on. That
    must surface here as an explicit, named limitation — see risk GH1.
#>

Set-StrictMode -Version Latest

function Get-LzGitHubInventory {
    <#
    .SYNOPSIS
        Inventory the GitHub account, org settings, repos, and Actions policy.
    .PARAMETER OwnerName
        The user or organization login the landing zone repository will live under.
    .PARAMETER RepositoryName
        The repository the broker intends to create. Probed for collision.
    .PARAMETER OwnershipModel
        personal | organization | enterprise — as declared in lz-config.json.
        Discovery verifies the declaration rather than trusting it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OwnerName,
        [string]$RepositoryName = '',
        [ValidateSet('personal', 'organization', 'enterprise')][string]$OwnershipModel = 'organization',
        [string]$EnterpriseSlug = ''
    )

    Write-LzSection 'GitHub discovery'
    $probes = [ordered]@{}

    # ── Authentication and token scopes ──────────────────────────────────────
    $probes['Authenticated identity'] = Invoke-LzProbe -Name 'Authenticated identity' -ForbiddenRemediation `
        'Run: gh auth login' -Probe {
        $me = Invoke-LzGh api user
        if (-not $me) { return @() }
        @([pscustomobject]@{
            Login = $me.login
            Id    = $me.id
            Type  = $me.type
            Name  = $me.name
        })
    }

    # Token scopes decide what the broker can do. gh surfaces them in the
    # response header, which `gh auth status` prints.
    $probes['Token scopes'] = Invoke-LzProbe -Name 'Token scopes' -Probe {
        $raw = (& gh auth status 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw $raw.Trim() }
        $scopes = @()
        if ($raw -match "Token scopes:\s*(.+)") {
            $scopes = ($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
        }
        if (-not $scopes) { return @() }
        @($scopes | ForEach-Object { [pscustomobject]@{ Scope = $_ } })
    }

    # ── Owner: is it actually a user or an org? ──────────────────────────────
    $probes['Owner account'] = Invoke-LzProbe -Name 'Owner account' -ForbiddenRemediation `
        "The signed-in token cannot read '$OwnerName'. Grant read:org, or confirm the owner login is correct." -Probe {
        $owner = Invoke-LzGh api "users/$OwnerName"
        if (-not $owner) { return @() }
        @([pscustomobject]@{
            Login             = $owner.login
            Type              = $owner.type          # 'User' or 'Organization'
            Plan              = if ($owner.PSObject.Properties.Name -contains 'plan') { $owner.plan.name } else { 'unknown' }
            PublicRepos       = $owner.public_repos
            DetectedAsOrg     = ($owner.type -eq 'Organization')
            DeclaredModel     = $OwnershipModel
            DeclarationMatches = (
                ($OwnershipModel -eq 'personal' -and $owner.type -eq 'User') -or
                ($OwnershipModel -in @('organization', 'enterprise') -and $owner.type -eq 'Organization')
            )
        })
    }

    # ── Organization settings (only meaningful for org/enterprise) ───────────
    if ($OwnershipModel -in @('organization', 'enterprise')) {
        $probes['Organization settings'] = Invoke-LzProbe -Name 'Organization settings' -ForbiddenRemediation `
            "Token lacks read:org for '$OwnerName'. Run: gh auth refresh -s read:org,admin:org" -Probe {
            $org = Invoke-LzGh api "orgs/$OwnerName"
            if (-not $org) { return @() }
            @([pscustomobject]@{
                Login                          = $org.login
                Plan                           = if ($org.PSObject.Properties.Name -contains 'plan') { $org.plan.name } else { 'unknown' }
                DefaultRepositoryPermission    = if ($org.PSObject.Properties.Name -contains 'default_repository_permission') { $org.default_repository_permission } else { $null }
                MembersCanCreatePrivateRepos   = if ($org.PSObject.Properties.Name -contains 'members_can_create_private_repositories') { $org.members_can_create_private_repositories } else { $null }
                MembersCanCreateRepos          = if ($org.PSObject.Properties.Name -contains 'members_can_create_repositories') { $org.members_can_create_repositories } else { $null }
                TwoFactorRequired              = if ($org.PSObject.Properties.Name -contains 'two_factor_requirement_enabled') { $org.two_factor_requirement_enabled } else { $null }
                WebCommitSignoffRequired       = if ($org.PSObject.Properties.Name -contains 'web_commit_signoff_required') { $org.web_commit_signoff_required } else { $null }
            })
        }

        $probes['Organization Actions policy'] = Invoke-LzProbe -Name 'Organization Actions policy' -ForbiddenRemediation `
            "Token lacks admin:org. The broker may still work, but the Actions policy could block the generated workflows without warning." -Probe {
            $p = Invoke-LzGh api "orgs/$OwnerName/actions/permissions"
            if (-not $p) { return @() }
            @([pscustomobject]@{
                EnabledRepositories = $p.enabled_repositories
                AllowedActions      = if ($p.PSObject.Properties.Name -contains 'allowed_actions') { $p.allowed_actions } else { 'all' }
            })
        }

        # An allow-list policy will reject the SHA-pinned third-party actions the
        # generated workflows use unless those actions are permitted.
        $probes['Allowed Actions patterns'] = Invoke-LzProbe -Name 'Allowed Actions patterns' -Probe {
            $p = Invoke-LzGh api "orgs/$OwnerName/actions/permissions/selected-actions"
            if (-not $p) { return @() }
            @([pscustomobject]@{
                GitHubOwnedAllowed = $p.github_owned_allowed
                VerifiedAllowed    = $p.verified_allowed
                PatternsAllowed    = ($p.patterns_allowed -join ', ')
            })
        }

        $probes['Organization runners'] = Invoke-LzProbe -Name 'Organization runners' -Probe {
            $r = Invoke-LzGh api "orgs/$OwnerName/actions/runners"
            if (-not $r -or $r.total_count -eq 0) { return @() }
            @($r.runners | ForEach-Object {
                [pscustomobject]@{ Name = $_.name; Status = $_.status; OS = $_.os; Labels = (($_.labels | ForEach-Object { $_.name }) -join ', ') }
            })
        }
    }

    # ── Enterprise ───────────────────────────────────────────────────────────
    if ($OwnershipModel -eq 'enterprise' -and $EnterpriseSlug) {
        $probes['Enterprise Actions policy'] = Invoke-LzProbe -Name 'Enterprise Actions policy' -ForbiddenRemediation `
            "Token lacks admin:enterprise for '$EnterpriseSlug'. Enterprise-level Actions restrictions override org settings, so an unreadable policy here is a real blind spot." -Probe {
            $p = Invoke-LzGh api "enterprises/$EnterpriseSlug/actions/permissions"
            if (-not $p) { return @() }
            @([pscustomobject]@{
                EnabledOrganizations = $p.enabled_organizations
                AllowedActions       = if ($p.PSObject.Properties.Name -contains 'allowed_actions') { $p.allowed_actions } else { 'all' }
            })
        }
    }

    # ── Existing repositories ────────────────────────────────────────────────
    $probes['Existing repositories'] = Invoke-LzProbe -Name 'Existing repositories' -ForbiddenRemediation `
        "Cannot list repositories for '$OwnerName'." -Probe {
        $repos = Invoke-LzGh repo list $OwnerName --limit 200 --json 'name,visibility,isArchived,defaultBranchRef,updatedAt'
        if (-not $repos) { return @() }
        @($repos | ForEach-Object {
            [pscustomobject]@{
                Name          = $_.name
                Visibility    = $_.visibility
                Archived      = $_.isArchived
                DefaultBranch = if ($_.defaultBranchRef) { $_.defaultBranchRef.name } else { '' }
                UpdatedAt     = $_.updatedAt
            }
        })
    }

    # ── Target repository collision + its existing controls ──────────────────
    if ($RepositoryName) {
        $target = "$OwnerName/$RepositoryName"

        $probes['Target repository'] = Invoke-LzProbe -Name 'Target repository' -Probe {
            # A 404 here is the good case: the name is free. gh exits non-zero on
            # 404, so we translate that into Empty rather than letting it surface
            # as an error.
            $out = & gh api "repos/$target" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                if ($out -match 'Not Found|404') { return @() }
                throw $out.Trim()
            }
            $r = $out | ConvertFrom-Json -Depth 20
            @([pscustomobject]@{
                FullName      = $r.full_name
                Visibility    = $r.visibility
                DefaultBranch = $r.default_branch
                Archived      = $r.archived
                PushedAt      = $r.pushed_at
                Note          = 'Repository already exists. The broker is idempotent and will reconcile rather than recreate, but review its contents before proceeding.'
            })
        }

        $probes['Target branch protection'] = Invoke-LzProbe -Name 'Target branch protection' -Probe {
            $out = & gh api "repos/$target/branches" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                if ($out -match 'Not Found|404') { return @() }
                throw $out.Trim()
            }
            $branches = $out | ConvertFrom-Json -Depth 20
            @($branches | Where-Object { $_.protected } | ForEach-Object {
                [pscustomobject]@{ Branch = $_.name; Protected = $_.protected }
            })
        }

        $probes['Target environments'] = Invoke-LzProbe -Name 'Target environments' -Probe {
            $out = & gh api "repos/$target/environments" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                if ($out -match 'Not Found|404') { return @() }
                throw $out.Trim()
            }
            $e = $out | ConvertFrom-Json -Depth 20
            if (-not $e -or $e.total_count -eq 0) { return @() }
            @($e.environments | ForEach-Object {
                [pscustomobject]@{
                    Name              = $_.name
                    ProtectionRules   = @($_.protection_rules).Count
                    CreatedAt         = $_.created_at
                }
            })
        }
    }

    foreach ($p in $probes.Values) { Write-LzProbeResult $p }

    # ── Derived capability assessment ────────────────────────────────────────
    $capabilities = Get-LzGitHubCapabilities -Probes $probes -OwnershipModel $OwnershipModel

    [pscustomobject]@{
        Domain       = 'GitHub'
        Owner        = $OwnerName
        Repository   = $RepositoryName
        Probes       = $probes
        Capabilities = $capabilities
    }
}

function Get-LzGitHubCapabilities {
    <#
    .SYNOPSIS
        Translate raw GitHub findings into what the broker will and will not be
        able to configure.
    .DESCRIPTION
        This is the function that keeps the factory honest about GH1. If the
        account tier cannot support environments, we say so here by name, so the
        readiness report can print it and the operator can decide — rather than
        the broker skipping the call and the deployment quietly having no
        approval gate.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Probes,
        [Parameter(Mandatory)][string]$OwnershipModel
    )

    $ownerProbe = $Probes['Owner account']
    $isOrg = $false
    $plan = 'unknown'

    if ($ownerProbe.Status -eq 'Ok') {
        $isOrg = [bool]$ownerProbe.Items[0].DetectedAsOrg
        $plan = [string]$ownerProbe.Items[0].Plan
    }

    # GitHub allows environments on private repos only for paid plans; they are
    # always available on public repos and on any org plan above Free.
    $freeTier = ($plan -eq 'free')
    $environmentsAvailable = $isOrg -or (-not $freeTier)
    $branchProtectionAvailable = $isOrg -or (-not $freeTier)

    $limitations = @()
    if (-not $environmentsAvailable) {
        $limitations += 'GitHub environments are unavailable on a Free personal account with private repositories. Every approval gate in the generated workflows would be inert, and applies would run with no human review.'
    }
    if (-not $branchProtectionAvailable) {
        $limitations += 'Branch protection is unavailable on a Free personal account with private repositories. Anyone with write access could push directly to the branch that triggers apply.'
    }

    $actionsProbe = if ($Probes.Contains('Organization Actions policy')) { $Probes['Organization Actions policy'] } else { $null }
    if ($actionsProbe -and $actionsProbe.Status -eq 'Ok') {
        $allowed = $actionsProbe.Items[0].AllowedActions
        if ($allowed -eq 'selected') {
            $limitations += "The organization restricts Actions to a selected allow-list. The generated workflows use SHA-pinned third-party actions, which will fail to start unless those actions are permitted."
        }
    }
    if ($actionsProbe -and $actionsProbe.Status -eq 'Forbidden') {
        $limitations += 'The organization Actions policy could not be read, so it is unknown whether the generated workflows are permitted to run. This is a blind spot, not a pass.'
    }

    [pscustomobject]@{
        DetectedOwnerType         = if ($isOrg) { 'Organization' } else { 'User' }
        DetectedPlan              = $plan
        DeclaredModel             = $OwnershipModel
        EnvironmentsAvailable     = $environmentsAvailable
        BranchProtectionAvailable = $branchProtectionAvailable
        Limitations               = $limitations
    }
}
