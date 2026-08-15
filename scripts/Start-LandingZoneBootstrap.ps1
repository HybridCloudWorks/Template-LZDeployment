#Requires -Version 7.0
<#
.SYNOPSIS
    Landing Zone Phase 0 Bootloader — Complete OIDC + GitHub + Azure orchestration

.DESCRIPTION
    Single entry point for bootstrapping a landing zone deployment. This script:

    PHASE 0 (LOCAL, THIS SCRIPT):
      1. Validate/install CLIs (az, gh, git, terraform)
      2. Authenticate to Azure and GitHub
      3. Create Entra apps and service principals (with proper least-privilege)
      4. Create federated OIDC credentials (scoped to branches/environments)
      5. Set up GitHub secrets and variables
      6. Create GitHub environments with proper protection
      7. Confirm the state backend (azurerm only — ADR 0015)
      8. Generate deployment report
      9. Create a ready-to-merge PR with all generated files

    PHASE 0.1 (WORKFLOW, DELEGATED TO workflow-010):
      - terraform init (azurerm backend, per-layer backend.hcl)
      - Create workload resource groups
      - Validate OIDC connectivity
      - Run first terraform plan

    IDEMPOTENT: Safe to re-run. State is tracked in .lz-bootloader-state.json

    SINGLE USER: Designed for admin/owner bootstrapping. Prompts for authentication.

    LANDING ZONE: Creates proper separation between human OAuth and CI/CD OIDC.
                  Identities come from the factory broker's plan builder
                  (factory/bootstrap/LZFactory.Bootstrap.psm1): minimal model
                  (default) = 1 read-only plan identity + 1 apply identity with
                  multi-subject federated credentials; per-environment model =
                  a plan/apply pair per environment. The legacy Main/Dev/Prod
                  matrix is no longer created — existing matrix estates are
                  detected and reported for operator-run remediation.

.EXAMPLE
    .\scripts\Start-LandingZoneBootstrap.ps1

.EXAMPLE
    .\scripts\Start-LandingZoneBootstrap.ps1 -SkipToolValidation -SkipAzureSetup

.EXAMPLE
    # Customer engagement: org-owned fork, wizard-exported config, team-gated
    # environments. azurerm is the only backend (ADR 0015);
    # TERRAFORM_CLOUD_ENABLED is always false.
    .\scripts\Start-LandingZoneBootstrap.ps1 `
        -Repository contoso-org/contoso-lz `
        -ConfigPath .\lz-config.json `
        -EnvironmentReviewers 'contoso-org/platform-approvers', 'jane-doe'
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipToolValidation,
    [switch]$SkipAzureSetup,
    [string]$ReportDirectory = ".reports/bootstrap",
    [string]$StateFile = ".lz-bootloader-state.json",

    # Target GitHub repository as <owner>/<name>. Secrets, variables,
    # environments, and every OIDC federated-credential subject
    # (repo:<owner>/<name>:...) are scoped to this repository. When omitted,
    # the script derives owner/name from the clone's origin remote
    # (gh repo view); the authenticated user's login is used only as a last
    # resort — which is WRONG for org-owned forks and warned about loudly.
    [ValidatePattern('^$|^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}/[A-Za-z0-9._-]{1,100}$')]
    [string]$Repository = '',

    # Path to a wizard-exported lz-config.json (contract:
    # factory/schema/lz-config.schema.json). Seeds org prefix, region/region
    # code, repository owner/name, backend type, TFC organization/workspace,
    # environments, and the sandbox subscription — so no per-customer value is
    # hardcoded. Values already in the state file are kept (idempotent re-run);
    # anything the config does not provide is prompted for interactively.
    [string]$ConfigPath = '',

    # State-backend selector. azurerm (Azure Storage, OIDC + AAD auth) is
    # the ONLY backend (ADR 0015); the parameter survives so a caller passing
    # a retired value gets a validation error, not silent acceptance.
    [ValidateSet('', 'azurerm')]
    [string]$Backend = '',

    # Required reviewers for the dev/prod/hub GitHub environments: user logins
    # and/or 'org/team' slugs. Default (empty) falls back to the bootstrapping
    # operator — SELF-APPROVAL in a single-owner repo, warned about loudly and
    # unacceptable for customer engagements.
    [string[]]$EnvironmentReviewers = @(),

    # Sandbox subscription ID. When supplied, the apply identity is granted
    # Role Based Access Control Administrator scoped to this subscription —
    # constrained by an ABAC delegation condition (may only write/delete
    # Contributor role assignments to service principals) — so
    # platform-management can write the sandbox-cleanup Contributor
    # assignment. Without it, that apply fails AuthorizationFailed.
    # When -ConfigPath is used, azure.subscriptions.sandbox from lz-config.json
    # fills this in automatically if the parameter is omitted.
    [string]$SandboxSubscriptionId = '',

    # Deliberately proceed without the sandbox RBAC grant even though the
    # deployment config enables the sandbox subscription. Without this switch,
    # sandbox-enabled + missing -SandboxSubscriptionId is a terminating error
    # (the alternative is a guaranteed AuthorizationFailed at apply time).
    [switch]$SkipSandboxRbac
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                           CONSTANTS & CONFIG                            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

$REPO_ROOT = Split-Path $PSScriptRoot -Parent
$STATE_FILE_PATH = Join-Path $REPO_ROOT $StateFile

# Minimum CLI versions
$MIN_VERSIONS = [ordered]@{
    'az'        = [version]'2.69.0'
    'gh'        = [version]'2.67.0'
    'git'       = [version]'2.43.0'
    'terraform' = [version]'1.9.0'
}

# Landing Zone service-principal naming convention: sp-terraform-{layer}-{environment}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                         OUTPUT FORMATTING                               ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Write-Header {
    param([string]$Title, [string]$Subtitle = "")
    Write-Host ""
    Write-Host ("╔" + ("═" * 78) + "╗") -ForegroundColor Cyan
    Write-Host ("║  " + $Title.PadRight(76) + "║") -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host ("║  " + $Subtitle.PadRight(76) + "║") -ForegroundColor Gray
    }
    Write-Host ("╚" + ("═" * 78) + "╝") -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Number, [string]$Title)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
    Write-Host "  PHASE ${Number}: $Title" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "  ⤳  $Message" -ForegroundColor White
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠  $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✗  $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "     $Message" -ForegroundColor Gray
}

function Write-Critical {
    param([string]$Message)
    Write-Host ""
    Write-Host "  🚨  CRITICAL: $Message" -ForegroundColor Red
    Write-Host ""
}

function Write-Manual {
    param([string]$Message)
    Write-Host "  👉  $Message" -ForegroundColor Magenta
}

function Assert-LastExitCode {
    <#
        Fails fast when an external CLI (az/gh/git) returned a non-zero exit
        code. Used after invocations whose stderr is suppressed (2>$null) so
        failures surface instead of being reported as success.
    #>
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed (exit code $LASTEXITCODE): $Operation"
    }
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                       STATE MANAGEMENT                                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Get-BootloaderState {
    if (Test-Path $STATE_FILE_PATH) {
        return (Get-Content $STATE_FILE_PATH -Raw | ConvertFrom-Json -AsHashtable)
    }
    return @{
        'timestamp'   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        'repo_root'   = $REPO_ROOT
        'completed'   = @()
    }
}

function Save-BootloaderState {
    param([hashtable]$State)
    $State['last_updated'] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $json = $State | ConvertTo-Json -Depth 5
    Set-Content -Path $STATE_FILE_PATH -Value $json -Encoding UTF8
}

function Mark-StepComplete {
    param([hashtable]$State, [string]$StepName)
    if ($State['completed'] -notcontains $StepName) {
        $State['completed'] += $StepName
    }
    Save-BootloaderState $State
}

function Test-StepComplete {
    param([hashtable]$State, [string]$StepName)
    return $State['completed'] -contains $StepName
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    TOOL VALIDATION & INSTALLATION                       ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Test-CliAvailable {
    param([string]$Tool)
    return $null -ne (Get-Command $Tool -ErrorAction SilentlyContinue)
}

function Get-CliVersion {
    param([string]$Tool)
    try {
        $raw = switch ($Tool) {
            'az' {
                $j = az version --output json 2>$null | ConvertFrom-Json
                $j.'azure-cli'
            }
            'terraform' {
                $j = terraform version -json 2>$null | ConvertFrom-Json
                $j.terraform_version -replace '\+.*$', ''
            }
            default {
                & $Tool --version 2>&1 | Select-Object -First 1
            }
        }

        if ($raw -match '(\d+\.\d+\.\d+)') {
            return [version]$Matches[1]
        }
        return $null
    } catch {
        return $null
    }
}

function Install-MissingCli {
    param([string]$Tool)

    Write-Warn "Tool not found: $Tool"
    Write-Host ""
    Write-Host "Installation instructions for ${Tool}:" -ForegroundColor Cyan

    switch ($Tool) {
        'az' {
            Write-Info "  Windows (choco):  choco install azure-cli"
            Write-Info "  Windows (winget): winget install Microsoft.AzureCLI"
            Write-Info "  macOS (brew):     brew install azure-cli"
            Write-Info "  Linux:            See https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        }
        'gh' {
            Write-Info "  Windows (choco):  choco install gh"
            Write-Info "  Windows (winget): winget install GitHub.cli"
            Write-Info "  macOS (brew):     brew install gh"
            Write-Info "  Linux:            See https://cli.github.com/manual/gh_help_installation"
        }
        'terraform' {
            Write-Info "  Windows (choco):  choco install terraform"
            Write-Info "  Windows (winget): winget install HashiCorp.Terraform"
            Write-Info "  macOS (brew):     brew install terraform"
            Write-Info "  Linux:            See https://developer.hashicorp.com/terraform/install"
        }
        'git' {
            Write-Info "  Windows (choco):  choco install git"
            Write-Info "  Windows (winget): winget install Git.Git"
            Write-Info "  macOS (brew):     brew install git"
            Write-Info "  Linux:            sudo apt install git (or equivalent)"
        }
    }

    Write-Manual "Install $Tool, then re-run this script."
    throw "Required CLI tool '$Tool' not found"
}

function Test-Cli-Prerequisites {
    Write-Section "1" "CLI Tool Validation"

    $allOk = $true
    foreach ($tool in $MIN_VERSIONS.Keys) {
        Write-Step "Checking $tool..."

        if (-not (Test-CliAvailable $tool)) {
            Install-MissingCli $tool
            $allOk = $false
            continue
        }

        $version = Get-CliVersion $tool
        $minVer = $MIN_VERSIONS[$tool]

        if ($null -eq $version) {
            Write-Warn "$tool installed but version check failed (expected >= $minVer)"
        } elseif ($version -lt $minVer) {
            Write-Warn "$tool $version (minimum recommended: $minVer)"
        } else {
            Write-OK "$tool $version"
        }
    }

    if (-not $allOk) {
        throw "Some CLI tools are missing or outdated. Install them and re-run."
    }

    Write-OK "All CLI prerequisites satisfied"
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    AUTHENTICATION & CONTEXT                             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Test-GhAuth {
    gh auth status 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-AzAuth {
    az account show --output json 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Confirm-Auth-Azure {
    Write-Section "2.1" "Azure Authentication"

    Write-Step "Checking Azure CLI authentication..."

    if (-not (Test-AzAuth)) {
        Write-Warn "Not authenticated to Azure. Starting browser login..."
        Write-Info "A browser window will open. Sign in with your Azure administrator account."
        az login --use-device-code 2>&1 | Out-Null

        if (-not (Test-AzAuth)) {
            throw "Azure login failed"
        }
    }

    $me = az account show --output json | ConvertFrom-Json
    Write-OK "Authenticated as: $($me.user.name)"
    Write-Info "Account:  $($me.user.name)"
    Write-Info "Tenant:   $($me.tenantId)"
    Write-Info "Sub:      $($me.name) ($($me.id))"

    return $me
}

function Confirm-Auth-GitHub {
    Write-Section "2.2" "GitHub Authentication"

    Write-Step "Checking GitHub CLI authentication..."

    if (-not (Test-GhAuth)) {
        Write-Warn "Not authenticated to GitHub. Starting browser login..."
        Write-Info "A browser window will open. Authenticate with your GitHub account."
        gh auth login --hostname github.com --git-protocol https `
            --scopes 'repo,workflow,read:org' --web 2>&1 | Out-Null

        if (-not (Test-GhAuth)) {
            throw "GitHub login failed"
        }
    }

    $user = gh api user --jq '.login' 2>&1
    Write-OK "Authenticated as: $user"

    return $user
}

function Import-LzConfig {
    <#
        Seeds the bootloader state from a wizard-exported lz-config.json
        (contract: factory/schema/lz-config.schema.json). Existing state keys
        win so re-runs stay idempotent; anything the config omits falls back
        to the interactive prompts in Gather-DeploymentConfig.
    #>
    param(
        [string]$Path,
        [hashtable]$State
    )

    Write-Section "0" "Configuration Import (lz-config.json)"

    if (-not (Test-Path $Path)) {
        throw "-ConfigPath not found: $Path"
    }

    Write-Step "Reading $Path"
    $config = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable

    if ($config.ContainsKey('schemaVersion') -and $config['schemaVersion'] -ne '2.0.0') {
        Write-Warn "lz-config schemaVersion is '$($config['schemaVersion'])' (this script implements 2.0.0) — seeded values may be incomplete"
    }

    # organization.companyShortName → org_prefix
    if (-not $State.ContainsKey('org_prefix') -and
        $config.ContainsKey('organization') -and $config['organization'].ContainsKey('companyShortName')) {
        $State['org_prefix'] = $config['organization']['companyShortName']
        Write-OK "Org prefix (from config): $($State['org_prefix'])"
    }

    # azure.primaryRegion / azure.primaryRegionCode → region / region_code
    if (-not $State.ContainsKey('region') -and $config.ContainsKey('azure')) {
        $az = $config['azure']
        if ($az.ContainsKey('primaryRegion') -and $az.ContainsKey('primaryRegionCode')) {
            $State['region'] = $az['primaryRegion']
            $State['region_code'] = $az['primaryRegionCode']
            Write-OK "Region (from config): $($State['region']) ($($State['region_code']))"
        }
    }

    # github.ownerName / github.repositoryName — used by Resolve-TargetRepository
    # when neither -Repository nor the clone's origin remote resolves.
    if ($config.ContainsKey('github')) {
        $gh = $config['github']
        if ($gh.ContainsKey('ownerName') -and $gh.ContainsKey('repositoryName')) {
            $State['config_github_owner'] = $gh['ownerName']
            $State['config_repo_name'] = $gh['repositoryName']
        }
    }

    # backend.type → backend_type (azurerm only — ADR 0015)
    if (-not $State.ContainsKey('backend_type') -and
        $config.ContainsKey('backend') -and $config['backend'].ContainsKey('type')) {
        $backendCfg = $config['backend']
        $State['backend_type'] = $backendCfg['type']
        Write-OK "State backend (from config): $($State['backend_type'])"
    }

    # backend.azurerm → state storage account coordinates (drive the state
    # data-plane role assignments in the identity plan)
    if ($config.ContainsKey('backend') -and $config['backend'].ContainsKey('azurerm')) {
        $azurermCfg = $config['backend']['azurerm']
        if (-not $State.ContainsKey('backend_rg') -and $azurermCfg.ContainsKey('resourceGroupName')) {
            $State['backend_rg'] = $azurermCfg['resourceGroupName']
        }
        if (-not $State.ContainsKey('backend_sa') -and $azurermCfg.ContainsKey('storageAccountName')) {
            $State['backend_sa'] = $azurermCfg['storageAccountName']
        }
    }

    # identity.cicdIdentityModel → identity_model. Absent key = 'minimal'
    # (broker contract: Get-LzCicdIdentityModel), so a config import never
    # falls through to the interactive prompt.
    if (-not $State.ContainsKey('identity_model')) {
        $identityModel = 'minimal'
        if ($config.ContainsKey('identity') -and $config['identity'].ContainsKey('cicdIdentityModel')) {
            $identityModel = $config['identity']['cicdIdentityModel']
        }
        $State['identity_model'] = $identityModel
        Write-OK "CI/CD identity model (from config): $($State['identity_model'])"
    }

    # azure.managementGroups.rootId → mg_root_id (the scope of the plan
    # identity's Reader and the apply identity's MG-root grants)
    if (-not $State.ContainsKey('mg_root_id') -and
        $config.ContainsKey('azure') -and $config['azure'].ContainsKey('managementGroups') -and
        $config['azure']['managementGroups'].ContainsKey('rootId')) {
        $State['mg_root_id'] = $config['azure']['managementGroups']['rootId']
        Write-OK "Management group root (from config): $($State['mg_root_id'])"
    }

    # environments.application → environments (only dev/prod are layers this
    # legacy script knows how to bootstrap; other application environments are
    # owned by the factory renderer).
    if (-not $State.ContainsKey('environments') -and
        $config.ContainsKey('environments') -and $config['environments'].ContainsKey('application')) {
        $known = @($config['environments']['application'] | Where-Object { $_ -in @('dev', 'prod') })
        if ($known.Count -gt 0) {
            $State['environments'] = $known
            Write-OK "Environments (from config): $($State['environments'] -join ', ')"
        }
    }

    # azure.subscriptions.sandbox → sandbox_enabled + sandbox_subscription_id
    if (-not $State.ContainsKey('sandbox_enabled') -and
        $config.ContainsKey('azure') -and $config['azure'].ContainsKey('subscriptions')) {
        $subs = $config['azure']['subscriptions']
        if ($subs.ContainsKey('sandbox') -and -not [string]::IsNullOrWhiteSpace($subs['sandbox'])) {
            $State['sandbox_enabled'] = $true
            $State['sandbox_subscription_id'] = $subs['sandbox']
            Write-OK "Sandbox subscription (from config): $($State['sandbox_subscription_id'])"
        } else {
            $State['sandbox_enabled'] = $false
            Write-OK "Sandbox subscription (from config): not provisioned"
        }
    }

    $State['config_path'] = $Path
    Save-BootloaderState $State
    Write-OK "Configuration import complete"
}

function Resolve-TargetRepository {
    <#
        Resolves the GitHub repository (owner + name) that receives secrets,
        variables, environments, and OIDC federated-credential subjects.

        Precedence:
          1. -Repository <owner>/<name> parameter (always wins, updates state)
          2. owner/name already in the state file (idempotent re-run)
          3. the clone's origin remote via `gh repo view` — correct for
             org-owned forks
          4. github.ownerName/repositoryName from -ConfigPath, if supplied
          5. LAST RESORT: the authenticated user's login — wrong for org-owned
             forks, so this path warns loudly. Repo name falls through to the
             interactive prompt in Gather-DeploymentConfig.
    #>
    param(
        [string]$RepositoryParameter,
        [hashtable]$State,
        [string]$FallbackOwner
    )

    Write-Step "Resolving target repository (owner/name)"

    if (-not [string]::IsNullOrWhiteSpace($RepositoryParameter)) {
        $owner, $name = $RepositoryParameter.Split('/', 2)
        $State['github_owner'] = $owner
        $State['repo_name'] = $name
        $State['repo_source'] = 'parameter'
        Save-BootloaderState $State
        Write-OK "Target repository (from -Repository): $owner/$name"
        return
    }

    if ($State.ContainsKey('github_owner') -and $State.ContainsKey('repo_name')) {
        Write-OK "Target repository (from state): $($State['github_owner'])/$($State['repo_name'])"
        return
    }

    Push-Location $REPO_ROOT
    try {
        $originJson = gh repo view --json owner,name 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$originJson")) {
            $origin = "$originJson" | ConvertFrom-Json
            $State['github_owner'] = $origin.owner.login
            $State['repo_name'] = $origin.name
            $State['repo_source'] = 'origin-remote'
            Save-BootloaderState $State
            Write-OK "Target repository (from origin remote): $($State['github_owner'])/$($State['repo_name'])"
            return
        }
    } finally {
        Pop-Location
    }

    if ($State.ContainsKey('config_github_owner') -and $State.ContainsKey('config_repo_name')) {
        $State['github_owner'] = $State['config_github_owner']
        $State['repo_name'] = $State['config_repo_name']
        $State['repo_source'] = 'lz-config'
        Save-BootloaderState $State
        Write-OK "Target repository (from lz-config.json): $($State['github_owner'])/$($State['repo_name'])"
        return
    }

    Write-Critical "Could not resolve the target repository from -Repository, the clone's origin remote, or -ConfigPath."
    Write-Warn "Falling back to the authenticated user's login '$FallbackOwner' as the repository owner."
    Write-Warn "This is WRONG if the client fork lives in a GitHub ORGANIZATION: secrets, environments,"
    Write-Warn "and every OIDC federated-credential subject would target $FallbackOwner/<repo> instead of"
    Write-Warn "<org>/<repo>. Re-run with -Repository <owner>/<name> if that is the case."
    $State['github_owner'] = $FallbackOwner
    $State['repo_source'] = 'user-login-fallback'
    Save-BootloaderState $State
}

function Gather-DeploymentConfig {
    param([hashtable]$State)

    Write-Section "3" "Deployment Configuration"

    # Org prefix
    if (-not $State.ContainsKey('org_prefix')) {
        $prefix = Read-Host "  Organization prefix for resource naming (e.g., acme, contoso)"
        $prefix = ($prefix -replace '[^a-z0-9]', '').ToLower()
        if ([string]::IsNullOrEmpty($prefix)) { $prefix = 'lz' }
        $State['org_prefix'] = $prefix
    }
    Write-OK "Org prefix: $($State['org_prefix'])"

    # Environment (dev/prod or both) — each menu choice maps to exactly what
    # it says; anything unrecognized falls back to full layering.
    if (-not $State.ContainsKey('environments')) {
        Write-Host ""
        Write-Host "  Which environments will you deploy to?" -ForegroundColor Cyan
        Write-Host "  [1] Dev only (rapid iteration)"
        Write-Host "  [2] Prod only (single tier)"
        Write-Host "  [3] Both Dev and Prod (full layering)"
        $env_choice = Read-Host "  Select [1-3]"

        $State['environments'] = switch ($env_choice) {
            '1' { @('dev') }
            '2' { @('prod') }
            default { @('dev', 'prod') }
        }
    }
    Write-OK "Environments: $($State['environments'] -join ', ')"

    # Region (seeded by -ConfigPath when supplied; old values remain the
    # interactive defaults only)
    if (-not $State.ContainsKey('region')) {
        $region = Read-Host "  Azure region (default: eastus)"
        if ([string]::IsNullOrEmpty($region)) { $region = 'eastus' }
        $State['region'] = $region.ToLower()

        $defaultCode = if ($State['region'] -eq 'eastus') { 'eus' } else { '' }
        $codePrompt = if ($defaultCode) { "  Region code for resource names (default: $defaultCode)" } else { "  Region code for resource names (e.g., eus2, scus)" }
        $region_code = Read-Host $codePrompt
        if ([string]::IsNullOrEmpty($region_code)) { $region_code = $defaultCode }
        if ([string]::IsNullOrEmpty($region_code)) {
            throw "A region code is required when the region is not eastus (used in resource names)"
        }
        $State['region_code'] = $region_code.ToLower()
    }
    Write-OK "Region: $($State['region']) ($($State['region_code']))"

    # Repository name (normally resolved by Resolve-TargetRepository; this
    # prompt is reached only on the user-login fallback path)
    if (-not $State.ContainsKey('repo_name')) {
        $repo_name = Read-Host "  GitHub repository name (default: HCW-Demo-LZDeployment)"
        if ([string]::IsNullOrEmpty($repo_name)) { $repo_name = 'HCW-Demo-LZDeployment' }
        $State['repo_name'] = $repo_name
    }
    Write-OK "Repository: $($State['repo_name'])"

    # State backend (seeded by -Backend or -ConfigPath). azurerm is the only
    # backend (ADR 0015); an unseeded run gets it without prompting.
    if (-not $State.ContainsKey('backend_type')) {
        $State['backend_type'] = 'azurerm'
    }
    Write-OK "State backend: $($State['backend_type'])"

    # azurerm backend: the state storage account coordinates drive the
    # Storage Blob Data Reader/Contributor grants in the identity plan
    # (contract #3: AAD-only state — shared keys are disabled, so without the
    # data-plane roles every init 403s on the blobs).
    if ($State['backend_type'] -eq 'azurerm') {
        if (-not $State.ContainsKey('backend_rg')) {
            $backend_rg = Read-Host "  State backend resource group (default: rg-tfstate-$($State['region_code'])-prod-01)"
            if ([string]::IsNullOrEmpty($backend_rg)) { $backend_rg = "rg-tfstate-$($State['region_code'])-prod-01" }
            $State['backend_rg'] = $backend_rg
        }
        if (-not $State.ContainsKey('backend_sa')) {
            $backend_sa = Read-Host "  State storage account name (from backend-bootstrap output, e.g. st$($State['org_prefix'])tfstatexxxx)"
            if ($backend_sa -notmatch '^[a-z0-9]{3,24}$') {
                throw "State storage account name must match ^[a-z0-9]{3,24}$ (got '$backend_sa')"
            }
            $State['backend_sa'] = $backend_sa
        }
        Write-OK "State account: $($State['backend_sa']) (rg: $($State['backend_rg']))"
    }

    # CI/CD identity model (seeded by -ConfigPath; minimal is the operator
    # default — 1 plan + 1 apply identity, scale driven by client selection)
    if (-not $State.ContainsKey('identity_model')) {
        Write-Host ""
        Write-Host "  Which CI/CD identity model should the bootstrap create?" -ForegroundColor Cyan
        Write-Host "  [1] Minimal (default): 1 plan + 1 apply identity, multi-subject federated credentials"
        Write-Host "  [2] Per-environment: a plan/apply pair per environment (2 x N identities)"
        $identity_choice = Read-Host "  Select [1-2]"

        $State['identity_model'] = if ($identity_choice -eq '2') { 'per-environment' } else { 'minimal' }
    }
    Write-OK "CI/CD identity model: $($State['identity_model'])"

    # Management group root: the global layer (management-groups/,
    # policy-baseline/) needs Management Group Contributor + Resource Policy
    # Contributor here — subscription-scope grants cannot satisfy it.
    if (-not $State.ContainsKey('mg_root_id')) {
        $mgDefault = if ($State.ContainsKey('tenant_id')) { $State['tenant_id'] } else { '' }
        $mgPrompt = if ($mgDefault) { "  Management group root ID (default: tenant root group $mgDefault)" } else { "  Management group root ID (tenant ID = Tenant Root Group)" }
        $mg_root = Read-Host $mgPrompt
        if ([string]::IsNullOrEmpty($mg_root)) { $mg_root = $mgDefault }
        if ([string]::IsNullOrEmpty($mg_root)) {
            throw "A management group root ID is required (use the tenant ID to root at the Tenant Root Group)"
        }
        $State['mg_root_id'] = $mg_root
    }
    Write-OK "Management group root: $($State['mg_root_id'])"

    # Sandbox subscription (seeded by -ConfigPath when supplied). Enabling it
    # requires -SandboxSubscriptionId — enforced in Main before OIDC setup.
    if (-not $State.ContainsKey('sandbox_enabled')) {
        $sandbox_choice = Read-Host "  Enable the sandbox subscription (sandbox-cleanup automation)? [y/N]"
        $State['sandbox_enabled'] = ($sandbox_choice -eq 'y')
    }
    Write-OK "Sandbox subscription: $(if ($State['sandbox_enabled']) { 'enabled' } else { 'disabled' })"

    Save-BootloaderState $State
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                 AZURE IDENTITIES & OIDC                                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Import-LzBootstrapBroker {
    <#
        Loads the factory bootstrap module. The broker owns identity-plan
        derivation (New-LzBootstrapPlan); this script deliberately consumes
        that single source of truth instead of keeping a divergent
        layers-x-environments copy, but keeps its own az-CLI execution and
        .lz-bootloader-state.json idempotency.
    #>
    $modulePath = Join-Path -Path $REPO_ROOT -ChildPath 'factory/bootstrap/LZFactory.Bootstrap.psm1'
    if (-not (Test-Path $modulePath)) {
        throw "Factory bootstrap module not found: $modulePath (the identity plan builder lives there)"
    }
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-OK "Identity plan builder loaded: factory/bootstrap/LZFactory.Bootstrap.psm1"
}

function Build-LzPlanConfig {
    <#
        Produces the config object New-LzBootstrapPlan consumes. A wizard
        export (-ConfigPath) is used verbatim; otherwise a minimal config is
        synthesized from the interactively gathered state. The synthesized
        platform list is @('bootstrap') so the apply identity receives the
        MG-root grants (Management Group Contributor + Resource Policy
        Contributor) that terraform/modules/management-groups/ and
        policy-baseline/ require — subscription-scope grants cannot satisfy
        the global layer.
    #>
    param(
        [hashtable]$State,
        [string]$GithubOwner,
        [string]$RepoName,
        [string]$SandboxSubscriptionId = ''
    )

    if ($State.ContainsKey('config_path') -and (Test-Path $State['config_path'])) {
        Write-OK "Identity plan input: wizard export $($State['config_path'])"
        return (Get-Content -Path $State['config_path'] -Raw | ConvertFrom-Json)
    }

    Write-OK "Identity plan input: synthesized from interactive configuration"

    $subscriptionId = $State['subscription_id']
    $applicationEnvs = @($State['environments'])
    $sandboxSub = ''
    if ($State['sandbox_enabled'] -and -not [string]::IsNullOrWhiteSpace($SandboxSubscriptionId)) {
        # Selecting the sandbox scales the estate: the apply identity gains
        # Contributor on the sandbox subscription (distinct scope) and an
        # environment:sandbox subject.
        $sandboxSub = $SandboxSubscriptionId
        if ($applicationEnvs -notcontains 'sandbox') { $applicationEnvs += 'sandbox' }
    }

    $backendConfig = if ($State['backend_type'] -eq 'azurerm') {
        [pscustomobject]@{
            type    = 'azurerm'
            azurerm = [pscustomobject]@{
                resourceGroupName  = $State['backend_rg']
                storageAccountName = $State['backend_sa']
                containerName      = 'tfstate'
                subscriptionId     = $subscriptionId
            }
        }
    } else {
        # backend_type is validated to azurerm before this point (ADR 0015);
        # an empty coordinates object only means the storage names were not
        # seeded, which the identity plan reports as a pending activity.
        [pscustomobject]@{ type = 'azurerm' }
    }

    return [pscustomobject]@{
        organization = [pscustomobject]@{ companyShortName = $State['org_prefix'] }
        github       = [pscustomobject]@{ ownerName = $GithubOwner; repositoryName = $RepoName }
        azure        = [pscustomobject]@{
            tenantId         = $State['tenant_id']
            managementGroups = [pscustomobject]@{ rootId = $State['mg_root_id'] }
            subscriptions    = [pscustomobject]@{
                management      = $subscriptionId
                connectivity    = $subscriptionId
                workloadProd    = $subscriptionId
                workloadNonProd = $subscriptionId
                sandbox         = $sandboxSub
            }
        }
        environments = [pscustomobject]@{
            platform    = @('bootstrap')
            application = @($applicationEnvs)
        }
        connectivity = [pscustomobject]@{ model = 'hub-spoke' }
        backend      = $backendConfig
        identity     = [pscustomobject]@{ cicdIdentityModel = $State['identity_model'] }
    }
}

function New-LzIdentityPrincipal {
    <#
        Idempotently ensures an app registration + service principal for one
        identity-plan record. Role assignments are NOT made here — they come
        from the plan record via Set-LzScopedRoleAssignment.
    #>
    param([string]$DisplayName)

    $existing = az ad app list --display-name $DisplayName --query "[0].appId" -o tsv 2>$null
    Assert-LastExitCode "az ad app list --display-name $DisplayName"
    if ([string]::IsNullOrWhiteSpace($existing)) {
        Write-Step "Creating app registration: $DisplayName"
        $appId = (az ad app create --display-name $DisplayName --output json | ConvertFrom-Json).appId
        Assert-LastExitCode "az ad app create --display-name $DisplayName"
        Write-OK "Created app registration"
    } else {
        $appId = $existing
        Write-OK "Using existing app registration: $DisplayName"
    }

    $spCheck = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv 2>$null
    Assert-LastExitCode "az ad sp list --filter appId eq $appId"
    if ([string]::IsNullOrWhiteSpace($spCheck)) {
        Write-Step "Creating service principal..."
        az ad sp create --id $appId --output none 2>$null
        Assert-LastExitCode "az ad sp create --id $appId"
        Start-Sleep -Seconds 5  # Wait for replication
        Write-OK "Created service principal"
    }

    $spObjId = az ad sp show --id $appId --query id -o tsv 2>$null
    Assert-LastExitCode "az ad sp show --id $appId"

    # Least-privilege invariant: no identity this script manages may hold Owner.
    $owner = az role assignment list `
        --assignee-object-id $spObjId `
        --query "[?roleDefinitionName=='Owner']" `
        --output json 2>$null | ConvertFrom-Json
    Assert-LastExitCode "az role assignment list (Owner check on $DisplayName)"
    if (($owner | Measure-Object).Count -gt 0) {
        Write-Critical "Service principal $DisplayName has Owner role! This violates least-privilege."
        throw "Owner role must be removed before proceeding"
    }

    return @{
        appId       = $appId
        spObjId     = $spObjId
        displayName = $DisplayName
    }
}

function Set-LzScopedRoleAssignment {
    <#
        Idempotent role assignment at an arbitrary scope (subscription,
        management group, or storage account resource ID). An optional ABAC
        condition constrains what the assignment can do (used for the
        sandbox RBAC Administrator delegation).
    #>
    param(
        [string]$SpObjId,
        [string]$Role,
        [string]$Scope,
        [string]$DisplayName,
        [string]$Condition = '',
        [string]$ConditionVersion = '2.0'
    )

    $existing = az role assignment list `
        --assignee-object-id $SpObjId `
        --role $Role `
        --scope $Scope `
        --query "[0].id" -o tsv 2>$null
    Assert-LastExitCode "az role assignment list (role '$Role' on $DisplayName at $Scope)"

    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Write-OK "Role present: $Role @ $Scope"
        return
    }

    Write-Step "Assigning role: $Role @ $Scope"
    $createArgs = @(
        'role', 'assignment', 'create',
        '--role', $Role,
        '--assignee-object-id', $SpObjId,
        '--assignee-principal-type', 'ServicePrincipal',
        '--scope', $Scope,
        '--output', 'none'
    )
    if (-not [string]::IsNullOrWhiteSpace($Condition)) {
        # ABAC delegation condition. Syntax per
        # https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-examples
        $createArgs += @('--condition', $Condition, '--condition-version', $ConditionVersion)
    }
    az @createArgs 2>$null
    Assert-LastExitCode "az role assignment create (role '$Role' on $DisplayName at $Scope)"
    Write-OK "Assigned $Role"
}

function Resolve-PublishedIdentity {
    <#
        Picks the identity record published to the repo-level GitHub secrets
        (AZURE_CLIENT_ID / AZURE_PLAN_CLIENT_ID). Minimal model: the 'shared'
        record. Per-environment model: prefer prod, fall back to dev, then the
        first record of that kind — the same prefer-prod-else-dev resolution
        the legacy main-prod/main-dev fallback used.
    #>
    param([hashtable]$Identities, [string]$Kind)

    foreach ($candidate in @("$Kind-shared", "$Kind-prod", "$Kind-dev")) {
        if ($Identities.ContainsKey($candidate)) { return $Identities[$candidate] }
    }
    foreach ($key in ($Identities.Keys | Sort-Object)) {
        if ($key -like "$Kind-*") { return $Identities[$key] }
    }
    return $null
}

function Find-LegacyIdentityEstate {
    <#
        Detects legacy-matrix identities (sp-terraform-{main,dev,prod,plan}-*
        naming) from bootloader state and from Entra, and records the evidence
        in state. NOTHING is deleted — the bootstrap report renders the
        operator-run remediation commands.
    #>
    param([hashtable]$State)

    Write-Step "Scanning for legacy-matrix identities (sp-terraform-*)"
    $prefix = $State['org_prefix']

    $legacyNames = @()
    foreach ($layer in @('main', 'dev', 'prod')) {
        foreach ($legacyEnv in @('dev', 'prod')) {
            $legacyNames += "sp-terraform-$layer-$legacyEnv-$prefix"
        }
    }
    $legacyNames += "sp-terraform-plan-ci-$prefix"

    $found = @{}

    # State evidence (a previous run of the matrix-era script)
    if ($State.ContainsKey('azure_sps')) {
        foreach ($key in $State['azure_sps'].Keys) {
            $record = $State['azure_sps'][$key]
            if ($record.ContainsKey('displayName') -and $record.ContainsKey('appId')) {
                $found[$record['displayName']] = $record['appId']
            }
        }
    }

    # Entra evidence (read-only probes)
    foreach ($name in $legacyNames) {
        if ($found.ContainsKey($name)) { continue }
        $appId = az ad app list --display-name $name --query "[0].appId" -o tsv 2>$null
        Assert-LastExitCode "az ad app list --display-name $name"
        if (-not [string]::IsNullOrWhiteSpace($appId)) {
            $found[$name] = $appId
        }
    }

    if ($found.Count -gt 0) {
        Write-Warn "Legacy-matrix identities detected ($($found.Count)); the bootstrap report will include operator-run remediation commands (nothing is deleted automatically)"
        $State['legacy_estate'] = $found
        Save-BootloaderState $State
    } else {
        Write-OK "No legacy-matrix identities found"
    }
}

function Add-OidcFederatedCredential {
    param(
        [string]$AppId,
        [string]$Name,
        [string]$Subject
    )

    # Check if exists
    $existing = az ad app federated-credential list --id $AppId --query "[?name=='$Name']" -o json 2>$null | ConvertFrom-Json
    Assert-LastExitCode "az ad app federated-credential list --id $AppId"
    if ($existing.Count -gt 0) {
        Write-OK "Federated credential already exists: $Name"
        return
    }

    Write-Step "Creating federated credential: $Name"
    $credFile = [System.IO.Path]::GetTempFileName()
    try {
        @{
            name        = $Name
            issuer      = "https://token.actions.githubusercontent.com"
            subject     = $Subject
            description = "GitHub Actions OIDC for Landing Zone ($Name)"
            audiences   = @("api://AzureADTokenExchange")
        } | ConvertTo-Json | Set-Content -Path $credFile -Encoding UTF8

        az ad app federated-credential create --id $AppId --parameters "@$credFile" --output none 2>$null
        Assert-LastExitCode "az ad app federated-credential create ($Name)"
        Write-OK "Created federated credential"
    } finally {
        Remove-Item $credFile -Force -ErrorAction SilentlyContinue
    }
}

function Setup-Azure-OIDC {
    param(
        [hashtable]$State,
        [string]$SubscriptionId,
        [string]$TenantId,
        [string]$GithubOwner,
        [string]$RepoName,
        [string]$SandboxSubscriptionId = '',
        [switch]$SandboxRbacSkipRequested
    )

    Write-Section "4" "Azure OIDC Identities & Federated Credentials (broker plan)"

    # The identity plan is built by the factory broker (single source of
    # truth); this script executes it with its own az CLI calls and state
    # tracking. Minimal model (default): 1 plan + 1 apply identity.
    # Per-environment model: a plan/apply pair per unique environment.
    Import-LzBootstrapBroker

    $planConfig = Build-LzPlanConfig `
        -State $State `
        -GithubOwner $GithubOwner `
        -RepoName $RepoName `
        -SandboxSubscriptionId $SandboxSubscriptionId
    $identityPlan = New-LzBootstrapPlan -Config $planConfig

    $identityModel = if ($identityPlan.PSObject.Properties['identityModel']) {
        $identityPlan.identityModel
    } else {
        'per-environment'
    }
    $identityRecords = @($identityPlan.identities)

    Write-Critical "RESOURCE CREATION: This section will create Azure resources (Entra apps, SPs, RBAC roles)"
    Write-Info "Identity model: $identityModel"
    Write-Info "Estimated resources:"
    Write-Info "  - $($identityRecords.Count) app registrations + service principals:"
    foreach ($record in $identityRecords) {
        Write-Info "      $($record.displayName) [$($record.kind)]"
    }
    Write-Info "  - federated credentials: one per OIDC subject (plus main-branch on plan, hub on apply)"
    Write-Info "  - RBAC: Reader @ MG root (plan); MG Contributor + Resource Policy Contributor @ MG root"
    Write-Info "          and Contributor per distinct subscription (apply); state data-plane roles (azurerm)"
    Write-Info ""
    $confirm = Read-Host "  Type 'CREATE' to proceed, or press ENTER to skip"

    if ($confirm -ne 'CREATE') {
        Write-Warn "Skipped Azure OIDC setup"
        return @{}
    }

    # Evidence pass: legacy-matrix identities are reported for operator-run
    # remediation, never deleted.
    Find-LegacyIdentityEstate -State $State

    $identities = @{}
    foreach ($record in $identityRecords) {
        $key = "$($record.kind)-$($record.environment)"
        Write-Step "Setting up identity: $($record.displayName) [$key]"

        $principal = New-LzIdentityPrincipal -DisplayName $record.displayName

        # Role assignments come in two record shapes (mirrors the broker's
        # Set-LzIdentity): minimal records carry explicit roleAssignments
        # (role+scope pairs, union across environments — possibly including
        # the ABAC-constrained sandbox spec with condition/conditionVersion);
        # per-environment records carry roles at one scope plus optional
        # stateRoleAssignments and optional delegatedRoleAssignments (the
        # broker's constrained sandbox grant).
        $assignmentSpecs = @()
        if ($record.PSObject.Properties['roleAssignments']) {
            $assignmentSpecs += @($record.roleAssignments)
        } else {
            foreach ($role in @($record.roles)) {
                $assignmentSpecs += [pscustomobject]@{ role = $role; scope = $record.scope }
            }
            if ($record.PSObject.Properties['stateRoleAssignments']) {
                $assignmentSpecs += @($record.stateRoleAssignments)
            }
        }
        if ($record.PSObject.Properties['delegatedRoleAssignments']) {
            $assignmentSpecs += @($record.delegatedRoleAssignments)
        }
        foreach ($spec in $assignmentSpecs) {
            # A spec-supplied ABAC condition MUST survive execution — dropping
            # it would create the sandbox RBAC Administrator grant
            # UNCONDITIONED, exactly what this migration forbids.
            $specCondition = ''
            $specConditionVersion = '2.0'
            if ($spec.PSObject.Properties['condition'] -and $spec.condition) {
                $specCondition = $spec.condition
                if ($spec.PSObject.Properties['conditionVersion'] -and $spec.conditionVersion) {
                    $specConditionVersion = $spec.conditionVersion
                }
            }
            Set-LzScopedRoleAssignment `
                -SpObjId $principal.spObjId `
                -Role $spec.role `
                -Scope $spec.scope `
                -DisplayName $record.displayName `
                -Condition $specCondition `
                -ConditionVersion $specConditionVersion
        }

        # One federated credential per subject, broker naming convention:
        # github-<kind>-<environment>. A minimal-model apply record has a
        # subject LIST (one environment:<name> per environment).
        $subjects = @($record.subject)
        foreach ($subject in $subjects) {
            $credentialName = if ($subject -match ':environment:(?<environmentName>[^:]+)$') {
                "github-$($record.kind)-$($Matches['environmentName'])"
            } else {
                "github-$($record.kind)-$($record.environment)"
            }
            Add-OidcFederatedCredential -AppId $principal.appId -Name $credentialName -Subject $subject
        }

        $identities[$key] = @{
            appId           = $principal.appId
            spObjId         = $principal.spObjId
            displayName     = $record.displayName
            kind            = $record.kind
            environment     = $record.environment
            subjects        = @($subjects)
            roleAssignments = @($assignmentSpecs | ForEach-Object {
                $conditionNote = if ($_.PSObject.Properties['condition'] -and $_.condition) { ' (ABAC-constrained)' } else { '' }
                "$($_.role)$conditionNote @ $($_.scope)"
            })
        }
    }

    $publishedPlan = Resolve-PublishedIdentity -Identities $identities -Kind 'plan'
    $publishedApply = Resolve-PublishedIdentity -Identities $identities -Kind 'apply'
    if ($null -eq $publishedPlan -or $null -eq $publishedApply) {
        throw "Identity plan produced no plan/apply pair — cannot continue (records: $($identities.Keys -join ', '))"
    }

    # Contract #2, extended for this repo's workflows:
    #  - plan identity: pull_request (exclusively) AND ref:refs/heads/main —
    #    the push-triggered READ-ONLY jobs (010 init/validate, the apply
    #    workflow's RBAC gate) authenticate on the branch subject and must
    #    never carry write RBAC.
    #  - apply identity: environment:<name> subjects ONLY — plus the 'hub'
    #    approval-gate environment terraform-apply.yml maps platform layers to.
    Write-Step "Binding main-branch (read-only) subject to plan identity: $($publishedPlan['displayName'])"
    Add-OidcFederatedCredential -AppId $publishedPlan['appId'] `
        -Name 'github-plan-main-branch' `
        -Subject "repo:$GithubOwner/$RepoName`:ref:refs/heads/main"
    $publishedPlan['subjects'] = @($publishedPlan['subjects']) + "repo:$GithubOwner/$RepoName`:ref:refs/heads/main"

    # Hub gate binding. terraform-apply.yml maps the PLATFORM layers (global,
    # platform-connectivity, platform-management) to environment:hub, and
    # those layers need the MG-root pair (Management Group Contributor +
    # Resource Policy Contributor). Minimal model: the single apply identity
    # carries the pair, so hub binds to it. Per-environment model: the pair
    # lives on the bootstrap-environment apply identity, so hub binds to THAT
    # identity and Set-GitHubSecrets env-scopes AZURE_CLIENT_ID to it on the
    # hub environment. Binding hub to apply-prod would AuthorizationFailed on
    # MG/policy operations; duplicating the MG-root pair onto a workload
    # identity would violate minimal-by-default. Subjects stay coherent:
    # hub (platform plane) -> platform-plane identity.
    $hubIdentity = if ($identities.ContainsKey('apply-bootstrap')) {
        $identities['apply-bootstrap']
    } else {
        $publishedApply
    }
    Write-Step "Binding hub approval-gate subject to: $($hubIdentity['displayName'])"
    Add-OidcFederatedCredential -AppId $hubIdentity['appId'] `
        -Name 'github-apply-hub' `
        -Subject "repo:$GithubOwner/$RepoName`:environment:hub"
    $hubIdentity['subjects'] = @($hubIdentity['subjects']) + "repo:$GithubOwner/$RepoName`:environment:hub"

    # platform-management writes a Contributor assignment into the sandbox
    # subscription (sandbox-cleanup automation), which needs
    # Microsoft.Authorization/roleAssignments/write there. platform-management
    # applies under environment:hub, so the grant goes to the HUB-BOUND
    # identity (the shared apply identity in minimal mode; apply-bootstrap in
    # per-environment mode) — RBAC Administrator scoped to the sandbox
    # subscription only, CONSTRAINED by an ABAC delegation condition: it may
    # only write/delete role assignments for the Contributor role and only to
    # service principals. Never Owner/UAA, never unconditioned, never in the
    # management subscription.
    if (-not [string]::IsNullOrWhiteSpace($SandboxSubscriptionId)) {
        Write-Step "Granting constrained sandbox RBAC Administrator to $($hubIdentity['displayName'])"
        $contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'  # Contributor built-in role
        # Two expressions are required because the attribute source differs
        # per action: Request for roleAssignments/write, Resource for
        # roleAssignments/delete (Microsoft Learn: delegate-role-assignments-examples).
        $sandboxCondition = (
            "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
            "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
            "@Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'})) AND " +
            "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
            "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$contributorRoleId} AND " +
            "@Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}))"
        )
        Set-LzScopedRoleAssignment `
            -SpObjId $hubIdentity['spObjId'] `
            -Role 'Role Based Access Control Administrator' `
            -Scope "/subscriptions/$SandboxSubscriptionId" `
            -DisplayName $hubIdentity['displayName'] `
            -Condition $sandboxCondition
        $hubIdentity['roleAssignments'] = @($hubIdentity['roleAssignments']) +
            "Role Based Access Control Administrator (ABAC: Contributor-to-ServicePrincipal only) @ /subscriptions/$SandboxSubscriptionId"
    } elseif ($SandboxRbacSkipRequested) {
        Write-Warn "Sandbox RBAC grant deliberately skipped (-SkipSandboxRbac): platform-management's sandbox-cleanup role assignment will fail (AuthorizationFailed) until the apply identity is granted constrained RBAC Administrator in the sandbox subscription"
    } else {
        Write-Warn "No -SandboxSubscriptionId supplied: platform-management's sandbox-cleanup role assignment will fail (AuthorizationFailed) until the apply identity is granted constrained RBAC Administrator in the sandbox subscription"
    }

    Write-OK "Azure OIDC setup complete ($identityModel model, $($identityRecords.Count) identities)"
    $State['azure_identities'] = $identities
    $State['identity_model'] = $identityModel
    $State['plan_environments'] = @($identityPlan.environments)
    Save-BootloaderState $State

    return $identities
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                   GITHUB SECRETS & VARIABLES                            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Set-GitHubSecrets {
    param(
        [hashtable]$State,
        [string]$GithubOwner,
        [string]$RepoName,
        [hashtable]$Identities
    )

    Write-Section "5" "GitHub Secrets & Variables Configuration"

    $repo = "$GithubOwner/$RepoName"

    # Compat shim: this repo's workflows keep their secret names unmodified —
    # AZURE_CLIENT_ID is the apply identity (environment-subject deploys),
    # AZURE_PLAN_CLIENT_ID is the read-only plan identity (pull_request and
    # main-branch subjects). Resolution: shared (minimal model), else the
    # prefer-prod-else-dev fallback (per-environment model).
    $applyIdentity = Resolve-PublishedIdentity -Identities $Identities -Kind 'apply'
    $planIdentity = Resolve-PublishedIdentity -Identities $Identities -Kind 'plan'
    if ($null -eq $applyIdentity -or $null -eq $planIdentity) {
        throw "Cannot publish GitHub secrets: identity records are incomplete (have: $($Identities.Keys -join ', '))"
    }
    Write-Step "Setting repo-level secrets (apply: $($applyIdentity['displayName']); plan: $($planIdentity['displayName']))..."

    foreach ($secret in @(
        @{ Name = 'AZURE_TENANT_ID';       Value = $State['tenant_id'] },
        @{ Name = 'AZURE_SUBSCRIPTION_ID'; Value = $State['subscription_id'] },
        @{ Name = 'AZURE_CLIENT_ID';       Value = $applyIdentity['appId'] },
        @{ Name = 'AZURE_PLAN_CLIENT_ID';  Value = $planIdentity['appId'] }
    )) {
        Write-Step "Setting secret: $($secret.Name)"
        $secret.Value | gh secret set $secret.Name --repo $repo 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Secret set: $($secret.Name)"
        } else {
            Write-Warn "Could not set secret $($secret.Name) via CLI"
        }
    }

    # Environment-scoped secrets. GitHub resolves environment secrets OVER
    # repo secrets, so a stale env-scoped AZURE_CLIENT_ID (the matrix-era
    # script set one on 'prod' = sp-terraform-prod-prod-*) would silently keep
    # deployments authenticating as the legacy over-privileged SP — and break
    # with AADSTS700016 the moment that app is deleted.
    $environmentScanList = @($State['environments'])
    if ($State.ContainsKey('plan_environments')) {
        $environmentScanList += @($State['plan_environments'])
    }
    $environmentScanList = @($environmentScanList + 'hub' | Select-Object -Unique)

    if ($State.ContainsKey('identity_model') -and $State['identity_model'] -eq 'per-environment') {
        # Per-environment model: each environment's jobs authenticate as their
        # own apply identity via an env-scoped override (this also overwrites
        # any stale matrix-era value).
        foreach ($env in $State['environments']) {
            if (-not $Identities.ContainsKey("apply-$env")) { continue }

            Write-Step "Setting environment-scoped secret for: $env"
            # The environment must exist before a secret can scope to it
            # (phase 6 re-PUTs it later with the protection payload).
            gh api -X PUT "repos/$repo/environments/$env" 2>$null | Out-Null
            Assert-LastExitCode "gh api PUT repos/$repo/environments/$env (pre-create for env secret)"
            $Identities["apply-$env"]['appId'] | gh secret set "AZURE_CLIENT_ID" --repo $repo --env $env 2>&1 | Out-Null
            Write-OK "Set env secret: AZURE_CLIENT_ID (env:$env = $($Identities["apply-$env"]['displayName']))"
        }

        # hub gates the platform layers; its jobs must authenticate as the
        # hub-bound identity that carries the MG-root pair (apply-bootstrap —
        # the same identity Setup-Azure-OIDC bound the environment:hub
        # subject to). The repo-level secret (apply-prod) must not leak into
        # hub jobs.
        if ($Identities.ContainsKey('apply-bootstrap')) {
            Write-Step "Setting environment-scoped secret for: hub (platform plane)"
            gh api -X PUT "repos/$repo/environments/hub" 2>$null | Out-Null
            Assert-LastExitCode "gh api PUT repos/$repo/environments/hub (pre-create for env secret)"
            $Identities['apply-bootstrap']['appId'] | gh secret set "AZURE_CLIENT_ID" --repo $repo --env hub 2>&1 | Out-Null
            Write-OK "Set env secret: AZURE_CLIENT_ID (env:hub = $($Identities['apply-bootstrap']['displayName']))"
        }
    } else {
        # Minimal model: the repo-level secret is the SINGLE source of truth —
        # delete any surviving env-scoped AZURE_CLIENT_ID override so a
        # migrated repo cannot keep deploying as a legacy matrix SP.
        $removedEnvSecrets = @()
        foreach ($envName in $environmentScanList) {
            gh api "repos/$repo/environments/$envName/secrets/AZURE_CLIENT_ID" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { continue }  # environment or secret absent

            Write-Warn "STALE environment-scoped AZURE_CLIENT_ID found on '$envName' — it overrides the repo-level secret and points at a legacy identity"
            gh api -X DELETE "repos/$repo/environments/$envName/secrets/AZURE_CLIENT_ID" 2>$null | Out-Null
            Assert-LastExitCode "gh api DELETE repos/$repo/environments/$envName/secrets/AZURE_CLIENT_ID"
            Write-OK "Deleted env-scoped AZURE_CLIENT_ID (env:$envName) — repo-level secret ($($applyIdentity['displayName'])) is now the single source"
            $removedEnvSecrets += $envName
        }
        if ($removedEnvSecrets.Count -gt 0) {
            $State['removed_env_secrets'] = @($removedEnvSecrets)
            Save-BootloaderState $State
        }
    }

    # GitHub Variables. TERRAFORM_CLOUD_ENABLED is always 'false' (ADR 0015);
    # the variable survives one release so older generated workflows that
    # still read it see an explicit false rather than an absent variable.
    Write-Step "Setting GitHub variables..."

    $tfcEnabled = 'false'

    $variables = @{
        'AZURE_REGION'            = $State['region']
        'AZURE_REGION_CODE'       = $State['region_code']
        'ORG_PREFIX'              = $State['org_prefix']
        'TF_VERSION'              = '1.9'
        'TERRAFORM_CLOUD_ENABLED' = $tfcEnabled
    }

    foreach ($var in $variables.GetEnumerator()) {
        Write-Step "Setting variable: $($var.Key)"
        gh variable set $var.Key --repo $repo --body $var.Value 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Variable set: $($var.Key) = $($var.Value)"
        }
    }

    Write-OK "GitHub secrets and variables configured"
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    GITHUB ENVIRONMENTS                                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Setup-GitHub-Environments {
    param(
        [string]$GithubOwner,
        [string]$RepoName,
        [hashtable]$State,
        [string[]]$EnvironmentReviewers = @()
    )

    Write-Section "6" "GitHub Environments"

    $repo = "$GithubOwner/$RepoName"

    # Protection payload sent with every environment PUT:
    #  - reviewers: from -EnvironmentReviewers (user logins and/or 'org/team'
    #    slugs). Default remains the bootstrapping operator, resolved at
    #    runtime — but a single operator-reviewer means SELF-APPROVAL in a
    #    single-owner repo, so that path warns loudly. An explicit human gate
    #    still always beats an empty one.
    #  - deployment_branch_policy: restrict deployments to protected branches.
    $reviewers = @()
    $reviewerLogin = ''
    if ($EnvironmentReviewers.Count -gt 0) {
        Write-Step "Resolving -EnvironmentReviewers for environment approval gate"
        foreach ($entry in $EnvironmentReviewers) {
            if ($entry -match '^([^/]+)/(.+)$') {
                $org = $Matches[1]
                $teamSlug = $Matches[2]
                $teamId = [int](gh api "orgs/$org/teams/$teamSlug" --jq '.id')
                Assert-LastExitCode "gh api orgs/$org/teams/$teamSlug (resolve reviewer team id)"
                $reviewers += @{ type = 'Team'; id = $teamId }
                Write-OK "Environment reviewer (team): $entry ($teamId)"
            } else {
                $userId = [int](gh api "users/$entry" --jq '.id')
                Assert-LastExitCode "gh api users/$entry (resolve reviewer user id)"
                $reviewers += @{ type = 'User'; id = $userId }
                Write-OK "Environment reviewer (user): $entry ($userId)"
            }
        }
    } else {
        Write-Step "Resolving bootstrap operator for environment approval gate"
        $reviewerId = [int](gh api user --jq '.id')
        Assert-LastExitCode "gh api user (resolve reviewer id)"
        $reviewerLogin = gh api user --jq '.login'
        Assert-LastExitCode "gh api user (resolve reviewer login)"
        $reviewers = @(@{ type = 'User'; id = $reviewerId })
        Write-Critical "Environment reviewer defaults to the bootstrapping operator ($reviewerLogin) — this is SELF-APPROVAL."
        Write-Warn "The operator who triggers a deployment can approve their own prod/hub gate."
        Write-Warn "Replace this before any customer engagement: re-run with"
        Write-Warn "-EnvironmentReviewers <login>[,<login>...] and/or <org>/<team-slug> entries."
    }

    $protectionPayload = @{
        reviewers                = $reviewers
        deployment_branch_policy = @{
            protected_branches     = $true
            custom_branch_policies = $false
        }
    } | ConvertTo-Json -Depth 4

    # Every environment the identity plan bound an apply subject to needs a
    # matching GitHub environment, or that federated credential can never be
    # presented. Union of the selected environments and the plan's
    # (bootstrap/platform environments included when a wizard config drives
    # the plan).
    $environmentNames = @($State['environments'])
    if ($State.ContainsKey('plan_environments')) {
        $environmentNames = @($environmentNames + @($State['plan_environments']) | Select-Object -Unique)
    }

    foreach ($env in $environmentNames) {
        Write-Step "Ensuring environment: $env"

        # Create/update environment with protection settings (idempotent)
        $protectionPayload | gh api -X PUT "repos/$repo/environments/$env" --input - 2>$null | Out-Null
        Assert-LastExitCode "gh api PUT repos/$repo/environments/$env"

        Write-OK "Environment exists: $env"
    }

    # Create 'hub' environment for approval gate
    Write-Step "Creating approval gate environment: hub"
    $protectionPayload | gh api -X PUT "repos/$repo/environments/hub" --input - 2>$null | Out-Null
    Assert-LastExitCode "gh api PUT repos/$repo/environments/hub"
    Write-Info "Note: 'hub' environment requires manual approval for prod deployments"
    if ($reviewerLogin) {
        Write-Info "      (gated on $reviewerLogin — self-approval; pass -EnvironmentReviewers to fix)"
    } else {
        Write-Info "      (gated on the reviewers passed via -EnvironmentReviewers)"
    }
    Write-OK "Environment exists: hub"

    Write-OK "GitHub environments configured"
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    TERRAFORM CLOUD                                      ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Generate-BootstrapReport {
    param(
        [hashtable]$State,
        [string]$ReportDir
    )

    Write-Section "8" "Bootstrap Report Generation"

    New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportPath = Join-Path $ReportDir "$timestamp-bootstrap-report.md"

    # Precompute dynamic sections: the identity inventory follows the broker
    # plan (minimal or per-environment), and the backend section follows the
    # backend_type decision.
    $spRows = ''
    $roleRows = ''
    if ($State.ContainsKey('azure_identities') -and $State['azure_identities'].Count -gt 0) {
        foreach ($idKey in ($State['azure_identities'].Keys | Sort-Object)) {
            $identityRecord = $State['azure_identities'][$idKey]
            $subjectList = (@($identityRecord['subjects']) -join '<br>')
            $spRows += "| $($identityRecord['displayName']) | $($identityRecord['kind']) | $($identityRecord['appId']) | $subjectList |`n"
            foreach ($roleEntry in @($identityRecord['roleAssignments'])) {
                $roleRows += "| $($identityRecord['displayName']) | $roleEntry |`n"
            }
        }
    } else {
        $spRows = "| (none — Azure OIDC setup was skipped) | — | — | — |`n"
        $roleRows = "| — | — |`n"
    }
    $spRows = $spRows.TrimEnd("`n")
    $roleRows = $roleRows.TrimEnd("`n")

    # Legacy-matrix estate remediation. Evidence comes from the Entra scan
    # (legacy_estate, recorded during phase 4) or, failing that, from an old
    # state file's azure_sps records. Commands are OPERATOR-RUN ONLY — this
    # script never deletes identities or role assignments.
    $legacyEvidence = @{}
    if ($State.ContainsKey('legacy_estate') -and $State['legacy_estate'].Count -gt 0) {
        $legacyEvidence = $State['legacy_estate']
    } elseif ($State.ContainsKey('azure_sps')) {
        foreach ($legacyKey in $State['azure_sps'].Keys) {
            $legacyRecord = $State['azure_sps'][$legacyKey]
            if ($legacyRecord.ContainsKey('displayName') -and $legacyRecord.ContainsKey('appId')) {
                $legacyEvidence[$legacyRecord['displayName']] = $legacyRecord['appId']
            }
        }
    }

    $remediationSection = ''
    if ($legacyEvidence.Count -gt 0) {
        $prefix = $State['org_prefix']
        $legacySubscription = $State['subscription_id'] ?? '<subscription-id>'
        $legacyMgRoot = $State['mg_root_id'] ?? '<mg-root-id>'
        $sandboxSubForReport = $State['sandbox_subscription_id'] ?? ''

        # Cutover target: the apply identity this run published (if phase 4 ran).
        $newApplyNote = 'the new apply identity (re-run this script to create and publish it)'
        if ($State.ContainsKey('azure_identities') -and $State['azure_identities'].Count -gt 0) {
            $publishedApplyRecord = Resolve-PublishedIdentity -Identities $State['azure_identities'] -Kind 'apply'
            if ($null -ne $publishedApplyRecord) {
                $newApplyNote = "``$($publishedApplyRecord['displayName'])`` (appId ``$($publishedApplyRecord['appId'])``)"
            }
        }
        $removedSecretsNote = if ($State.ContainsKey('removed_env_secrets') -and @($State['removed_env_secrets']).Count -gt 0) {
            "This run already deleted stale environment-scoped AZURE_CLIENT_ID overrides on: $(@($State['removed_env_secrets']) -join ', ')."
        } else {
            "Also verify no environment-scoped AZURE_CLIENT_ID override survives (Settings → Environments → <env> → Secrets) — environment secrets override repo secrets."
        }

        # Dead-weight apps. CAUTION: dev-only estates published
        # sp-terraform-main-dev-* AS the live AZURE_CLIENT_ID, and secret
        # values cannot be read back via API — deletion is gated on the
        # pre-flight verification below.
        $deadNames = @(
            "sp-terraform-dev-dev-$prefix",
            "sp-terraform-dev-prod-$prefix",
            "sp-terraform-prod-dev-$prefix",
            "sp-terraform-main-dev-$prefix"
        )
        $deadCommands = ''
        foreach ($deadName in $deadNames) {
            if ($legacyEvidence.ContainsKey($deadName)) {
                $caution = if ($deadName -eq "sp-terraform-main-dev-$prefix") {
                    ' — on dev-only estates this WAS the live AZURE_CLIENT_ID; pre-flight check is MANDATORY'
                } else { '' }
                $deadCommands += "az ad app delete --id $($legacyEvidence[$deadName])  # $deadName$caution`n"
            }
        }
        if (-not $deadCommands) { $deadCommands = "# (none of the four dead-weight apps were found)`n" }

        # RBAC Administrator removals:
        #  - legacy dev-*/prod-* layer SPs: unconditioned grant at the legacy
        #    deployment subscription;
        #  - legacy main-* SPs: the matrix-era sandbox grant was UNCONDITIONED
        #    RBAC Administrator at the sandbox subscription — the highest
        #    residual privilege in the estate.
        $rbacAdminCommands = ''
        foreach ($legacyName in ($legacyEvidence.Keys | Sort-Object)) {
            if ($legacyName -match "^sp-terraform-(dev|prod)-") {
                $rbacAdminCommands += "az role assignment delete --assignee $($legacyEvidence[$legacyName]) --role `"Role Based Access Control Administrator`" --scope /subscriptions/$legacySubscription  # $legacyName`n"
            }
        }
        foreach ($legacyName in ($legacyEvidence.Keys | Sort-Object)) {
            if ($legacyName -match "^sp-terraform-main-") {
                $legacyAppId = $legacyEvidence[$legacyName]
                if (-not [string]::IsNullOrWhiteSpace($sandboxSubForReport)) {
                    $rbacAdminCommands += "az role assignment delete --assignee $legacyAppId --role `"Role Based Access Control Administrator`" --scope /subscriptions/$sandboxSubForReport  # $legacyName (UNCONDITIONED sandbox grant)`n"
                } else {
                    $rbacAdminCommands += "az role assignment list --assignee $legacyAppId --role `"Role Based Access Control Administrator`" --all -o table  # $legacyName`: locate the unconditioned sandbox-subscription grant, then delete it with: az role assignment delete --assignee $legacyAppId --role `"Role Based Access Control Administrator`" --scope /subscriptions/<sandbox-subscription-id>`n"
                }
            }
        }
        if (-not $rbacAdminCommands) { $rbacAdminCommands = "# (no legacy RBAC Administrator grants found)`n" }

        # Retirement of the remaining (wired) legacy identities. The legacy
        # main SP keeps ref:refs/heads/main + environment:* subjects WITH
        # Contributor — a write-capable identity on a branch subject, exactly
        # the contract-#2 violation this migration eliminates. It must not
        # survive cutover.
        $retireCommands = ''
        foreach ($legacyName in ($legacyEvidence.Keys | Sort-Object)) {
            if ($legacyName -in $deadNames) { continue }
            $legacyAppId = $legacyEvidence[$legacyName]
            $retireCommands += "az ad app federated-credential list --id $legacyAppId --query `"[].{name:name,subject:subject}`" -o table  # $legacyName`: inspect remaining OIDC subjects`n"
            if ($legacyName -match "^sp-terraform-main-") {
                $retireCommands += "az ad app federated-credential delete --id $legacyAppId --federated-credential-id github-main-branch  # $legacyName`: remove the write-capable BRANCH subject first`n"
                foreach ($legacyCredEnv in @('dev', 'prod', 'hub')) {
                    $retireCommands += "az ad app federated-credential delete --id $legacyAppId --federated-credential-id github-environment-$legacyCredEnv  # $legacyName`n"
                }
            }
            $retireCommands += "az ad app delete --id $legacyAppId  # $legacyName — retire once cutover is verified`n"
        }
        if (-not $retireCommands) { $retireCommands = "# (no remaining legacy identities to retire)`n" }

        # MG-root grants for the legacy apply SP — legitimate ONLY on the
        # explicit no-cutover path; the default motion is cutover + retirement.
        $legacyMainName = if ($legacyEvidence.ContainsKey("sp-terraform-main-prod-$prefix")) {
            "sp-terraform-main-prod-$prefix"
        } elseif ($legacyEvidence.ContainsKey("sp-terraform-main-dev-$prefix")) {
            "sp-terraform-main-dev-$prefix"
        } else { '' }
        $mgGrantCommands = if ($legacyMainName) {
            "az role assignment create --assignee $($legacyEvidence[$legacyMainName]) --role `"Management Group Contributor`" --scope /providers/Microsoft.Management/managementGroups/$legacyMgRoot  # $legacyMainName`n" +
            "az role assignment create --assignee $($legacyEvidence[$legacyMainName]) --role `"Resource Policy Contributor`" --scope /providers/Microsoft.Management/managementGroups/$legacyMgRoot  # $legacyMainName"
        } else {
            "# (no legacy main-layer SP found)"
        }

        $remediationSection = @"

## Legacy Identity Estate — Remediation (OPERATOR-RUN, nothing executed)

Legacy-matrix identities (sp-terraform-{layer}-{env}-$prefix) were detected.
The commands below are **recommendations for the operator to review and run
manually** — this script never deletes identities or role assignments.

Detected legacy identities:

$(($legacyEvidence.Keys | Sort-Object | ForEach-Object { "- $_ (``$($legacyEvidence[$_])``)" }) -join "`n")

### 0. Pre-flight — verify the live secrets first

GitHub secret values cannot be read back via the API. Before deleting ANY app
below, confirm in **Settings → Secrets and variables → Actions** (repo AND
every environment) that ``AZURE_CLIENT_ID`` no longer references a legacy
appId. Expected value after cutover: $newApplyNote.
$removedSecretsNote

### 1. Delete the dead-weight apps (delete ONLY after the pre-flight check confirms AZURE_CLIENT_ID no longer references them)

``````bash
$($deadCommands.TrimEnd("`n"))
``````

### 2. Remove the legacy RBAC Administrator grants (highest residual privilege)

Includes the matrix-era UNCONDITIONED sandbox-subscription grant on the legacy
main SP — the new estate replaces it with an ABAC-constrained grant on the
hub-bound apply identity.

``````bash
$($rbacAdminCommands.TrimEnd("`n"))
``````

### 3. After cutover: retire the remaining legacy identities

The legacy main SP still holds ``ref:refs/heads/main`` and ``environment:*``
subjects WITH Contributor — a write-capable identity on a branch subject
(contract #2 violation). Remove its federated credentials, then delete the app.

``````bash
$($retireCommands.TrimEnd("`n"))
``````

### 4. ONLY if NOT cutting over: MG-root grants for the legacy apply SP

Skip this section on the normal cutover path — the new apply identity already
carries these grants. Run it only if you deliberately keep deploying as the
legacy SP (and then still complete sections 1-2):

``````bash
$mgGrantCommands
``````
"@
    }

    # Stale env-scoped secret deletions performed by Set-GitHubSecrets
    # (minimal-mode migration hygiene) are part of the record.
    $staleSecretLine = if ($State.ContainsKey('removed_env_secrets') -and @($State['removed_env_secrets']).Count -gt 0) {
        "`n- ⚠ Deleted stale environment-scoped AZURE_CLIENT_ID overrides (they shadowed the repo-level secret): $(@($State['removed_env_secrets']) -join ', ')"
    } else { '' }

    $backendSection = if ($State.ContainsKey('backend_type') -and $State['backend_type'] -eq 'azurerm') {
        @"
| Setting | Value |
|---------|-------|
| Backend | azurerm (Azure Storage, AAD-auth) |
| TERRAFORM_CLOUD_ENABLED | false |
"@
    } else {
        @"
| Setting | Value |
|---------|-------|
| Backend | azurerm (state coordinates not seeded — supply backend.azurerm in lz-config.json) |
"@
    }

    $report = @"
# Landing Zone Phase 0 Bootstrap Report

**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Status**: ✓ Bootstrap Complete

## Configuration

| Key | Value |
|-----|-------|
| Organization Prefix | $($State['org_prefix']) |
| Environments | $($State['environments'] -join ', ') |
| CI/CD Identity Model | $($State['identity_model'] ?? 'minimal') |
| Management Group Root | $($State['mg_root_id'] ?? 'not set') |
| Region | $($State['region']) ($($State['region_code'])) |
| Repository | $($State['github_owner'])/$($State['repo_name']) |
| State Backend | $($State['backend_type'] ?? 'azurerm') |
| Azure Tenant | $($State['tenant_id']) |
| Azure Subscription | $($State['subscription_id']) |

## OIDC Identities (broker plan)

| Identity | Kind | App ID | OIDC Subjects |
|----------|------|--------|---------------|
$spRows

### Role Assignments

| Identity | Role @ Scope |
|----------|--------------|
$roleRows

## GitHub Configuration

- ✓ Repository Secrets: AZURE_CLIENT_ID (apply), AZURE_PLAN_CLIENT_ID (plan), AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
- ✓ GitHub Variables: Org prefix, region, TF version, etc.
- ✓ Environments: $((@(@($State['environments']) + @($State['plan_environments'] ?? @()) + 'hub') | Select-Object -Unique) -join ', ')
- ✓ Federated Credentials: one per OIDC subject (plan: pull_request + main branch; apply: environments only)$staleSecretLine

## State Backend

$backendSection
$remediationSection

## Next Steps (Workflow 010)

1. ✓ Phase 0 (THIS SCRIPT): Local bootstrap complete
2. ⏭ Phase 0.1 (WORKFLOW 010): Run on next PR/commit
   - Initialize Terraform with the configured state backend
   - Create workload resource groups
   - Validate OIDC connectivity
   - First terraform plan

## Rollback Instructions

If you need to restart:
1. Delete .lz-bootloader-state.json to reset state tracking
2. Re-run this script (idempotent)
3. It will skip already-created resources

## Security Notes

- All identities use OIDC federated credentials (no client secrets stored)
- Plan identity: Reader at the management group root (+ Storage Blob Data Reader on the state account for azurerm) — read-only, can never mutate
- Apply identity: Management Group Contributor + Resource Policy Contributor at the MG root (required by the global layer), Contributor per distinct subscription, Storage Blob Data Contributor on the state account (azurerm)
- pull_request and main-branch (read-only) OIDC subjects bound ONLY to the plan identity; the apply identity holds environment:<name> subjects exclusively
- RBAC Administrator appears nowhere except (when the sandbox is selected) on the apply identity, scoped to the sandbox subscription and constrained by an ABAC delegation condition (Contributor-to-ServicePrincipal role assignments only)
- No Owner or User Access Administrator roles assigned to any identity
- GitHub secrets are encrypted and never exposed in logs

## Support

For issues, check:
- .reports/bootstrap/ — Previous bootstrap reports
- docs/bootstrap/ — Detailed bootstrap documentation
- GitHub Actions logs — Workflow execution logs
"@

    Set-Content -Path $reportPath -Value $report -Encoding UTF8
    Write-OK "Bootstrap report saved: $reportPath"

    return $reportPath
}

function Create-BootstrapPR {
    param(
        [string]$GithubOwner,
        [string]$RepoName
    )

    Write-Section "9" "Creating Bootstrap PR (Optional)"

    Write-Manual "Would you like to create a PR with bootstrap artifacts?"
    Write-Info "This creates a branch with any generated files (terraform config, docs, etc.)"
    Write-Host ""

    $createPR = Read-Host "Create PR? [y/N]"

    if ($createPR -ne 'y') {
        Write-Warn "PR creation skipped"
        Write-Info "You can create it manually later if needed"
        return
    }

    $branchName = "bootstrap/phase-0-oidc-setup-$(Get-Date -Format 'yyyyMMdd')"

    Write-Step "Creating branch: $branchName"
    Push-Location $REPO_ROOT
    try {
        git checkout -b $branchName 2>&1 | Out-Null

        # Stage bootstrap artifacts
        git add ".lz-bootloader-state.json" ".reports/bootstrap/" 2>&1 | Out-Null

        if ((git status --porcelain | Measure-Object).Count -eq 0) {
            Write-Warn "No changes to commit"
            git checkout main 2>&1 | Out-Null
            return
        }

        git commit -m "chore: phase 0 bootstrap OIDC and GitHub setup

- Created OIDC identities from the broker plan (plan + apply)
- Configured federated credentials (GitHub Actions OIDC)
- Set GitHub secrets and variables
- Configured GitHub environments
- Configured the Terraform state backend

This enables automated infrastructure deployments via GitHub Actions.
Run workflow 010 after merging to initialize Terraform." 2>&1 | Out-Null

        Write-Step "Pushing branch..."
        git push --set-upstream origin $branchName 2>&1 | Out-Null

        Write-Step "Creating pull request..."
        $prUrl = gh pr create `
            --title "chore: phase 0 bootstrap OIDC and GitHub setup" `
            --body "## Bootstrap Phase 0

This PR completes Phase 0 bootstrap for the landing zone:
- OIDC service principals created
- GitHub OIDC federated credentials configured
- Terraform state backend configured

✅ Ready to merge to main
⏭ After merge, run workflow 010 to deploy" `
            --base main `
            --head $branchName 2>&1

        Write-OK "Pull request created"
        Write-Info "URL: $prUrl"
        Write-Manual "Review and merge to continue to Phase 0.1"

    } finally {
        Pop-Location
    }
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                          MAIN ORCHESTRATION                             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Main {
    Clear-Host
    Write-Header "Landing Zone Phase 0 Bootloader" "Complete OIDC + GitHub + TFC orchestration"

    $state = Get-BootloaderState

    try {
        # Phase 0: optional lz-config.json import — first, so seeded values
        # shape the later prompts and phase selection
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            Import-LzConfig -Path $ConfigPath -State $state
            Mark-StepComplete $state "config-imported"
        }

        # An explicit -Backend outranks the config and any prior answer
        if (-not [string]::IsNullOrWhiteSpace($Backend)) {
            $state['backend_type'] = $Backend
            Save-BootloaderState $state
        }

        # Phase 1: Tool validation
        if (-not $SkipToolValidation) {
            Test-Cli-Prerequisites
            Mark-StepComplete $state "cli-validation"
        }

        # Phase 2: Authentication
        if (-not $SkipAzureSetup) {
            $azAccount = Confirm-Auth-Azure
            $state['tenant_id'] = $azAccount.tenantId
            $state['subscription_id'] = $azAccount.id
            $state['subscription_name'] = $azAccount.name
            Save-BootloaderState $state
            Mark-StepComplete $state "azure-auth"
        }

        $ghUser = Confirm-Auth-GitHub
        $state['github_user'] = $ghUser
        Save-BootloaderState $state
        Mark-StepComplete $state "github-auth"

        # Target repository (owner/name): -Repository param, else the clone's
        # origin remote — NOT the operator's login, which is wrong for
        # org-owned forks. Everything downstream (secrets, environments, OIDC
        # subjects, PR) uses this resolution.
        Resolve-TargetRepository -RepositoryParameter $Repository -State $state -FallbackOwner $ghUser

        # Phase 3: Configuration (fills anything -ConfigPath did not seed;
        # also prompts for repo name on the owner-fallback path above)
        Gather-DeploymentConfig $state
        Mark-StepComplete $state "config-gathered"

        $repoOwner = $state['github_owner']
        $repoName = $state['repo_name']

        # azurerm is the only backend (ADR 0015): the legacy hcp-terraform
        # override and its auth phase were retired with the render path's
        # dual-backend feature.
        if ($state['backend_type'] -ne 'azurerm') {
            throw "backend_type '$($state['backend_type'])' is not supported: azurerm is the only state backend (ADR 0015)."
        }

        # Sandbox RBAC enforcement: sandbox enabled + no subscription ID is a
        # guaranteed AuthorizationFailed at apply time — stop here instead,
        # unless the operator deliberately opted out with -SkipSandboxRbac.
        $effectiveSandboxSubscriptionId = $SandboxSubscriptionId
        if ([string]::IsNullOrWhiteSpace($effectiveSandboxSubscriptionId) -and $state.ContainsKey('sandbox_subscription_id')) {
            $effectiveSandboxSubscriptionId = $state['sandbox_subscription_id']
        }
        if ($state['sandbox_enabled'] -and -not $SkipSandboxRbac -and
            [string]::IsNullOrWhiteSpace($effectiveSandboxSubscriptionId)) {
            Write-Fail "Sandbox subscription is enabled, but no sandbox subscription ID is available."
            throw ("The deployment config enables the sandbox subscription, but -SandboxSubscriptionId was not supplied " +
                "and lz-config.json did not provide azure.subscriptions.sandbox. Without the RBAC grant, " +
                "platform-management's sandbox-cleanup role assignment fails AuthorizationFailed at apply. " +
                "Re-run with -SandboxSubscriptionId <guid>, or pass -SkipSandboxRbac to proceed deliberately without the grant.")
        }

        # Phase 4: Azure OIDC setup
        if (-not $SkipAzureSetup) {
            $sps = Setup-Azure-OIDC `
                -State $state `
                -SubscriptionId $state['subscription_id'] `
                -TenantId $state['tenant_id'] `
                -GithubOwner $repoOwner `
                -RepoName $repoName `
                -SandboxSubscriptionId $(if ($SkipSandboxRbac) { '' } else { $effectiveSandboxSubscriptionId }) `
                -SandboxRbacSkipRequested:$SkipSandboxRbac

            if ($sps.Count -gt 0) {
                Mark-StepComplete $state "azure-oidc-setup"
            }
        }

        # Phase 5: GitHub secrets
        # Guard key presence explicitly — under StrictMode, indexing a missing
        # key then calling .Count on $null would fail. A pre-upgrade state
        # file carries only azure_sps (legacy matrix) — that never reaches
        # here; it is routed to the remediation section of the report instead.
        if ($state.ContainsKey('azure_identities') -and $state['azure_identities'].Count -gt 0) {
            Set-GitHubSecrets `
                -State $state `
                -GithubOwner $repoOwner `
                -RepoName $repoName `
                -Identities $state['azure_identities']

            Mark-StepComplete $state "github-secrets"
        } elseif ($state.ContainsKey('azure_sps')) {
            Write-Warn "State file contains only legacy-matrix identities (azure_sps); GitHub secrets were NOT updated."
            Write-Warn "Re-run phase 4 (type CREATE) to provision the minimal identity estate, then re-run."
        }

        # Phase 6: GitHub environments
        Setup-GitHub-Environments `
            -GithubOwner $repoOwner `
            -RepoName $repoName `
            -State $state `
            -EnvironmentReviewers $EnvironmentReviewers

        Mark-StepComplete $state "github-environments"

        # Phase 7 (Terraform Cloud) was retired by ADR 0015: state lives in
        # Azure Storage with OIDC + Azure AD auth; there is nothing to set up.

        # Phase 8: Report
        $reportPath = Generate-BootstrapReport -State $state -ReportDir $ReportDirectory
        Mark-StepComplete $state "report-generated"

        # Phase 9: PR
        Create-BootstrapPR -GithubOwner $repoOwner -RepoName $repoName

        # Summary
        Write-Section "COMPLETE" "Phase 0 Bootstrap Summary"
        Write-OK "✓ CLI tools validated"
        Write-OK "✓ Azure authentication confirmed"
        Write-OK "✓ GitHub authentication confirmed"
        Write-OK "✓ Deployment configuration gathered"
        Write-OK "✓ OIDC service principals created"
        Write-OK "✓ Federated credentials configured"
        Write-OK "✓ GitHub secrets set"
        Write-OK "✓ GitHub environments created"
        Write-OK "✓ State backend: azurerm (OIDC + Azure AD auth)"
        Write-OK "✓ Bootstrap report generated"

        Write-Host ""
        Write-Info "Report: $reportPath"
        Write-Info "State: $STATE_FILE_PATH"
        Write-Host ""
        Write-Manual "NEXT STEPS:"
        Write-Info "1. Review and merge any bootstrap PR"
        Write-Info "2. Run workflow 010 to initialize Terraform"
        Write-Info "3. Confirm terraform plan output"
        Write-Info "4. Merge or approve for terraform apply"

    } catch {
        Write-Host ""
        Write-Fail "Bootstrap failed: $_"
        Write-Info ""
        Write-Info "Fix the issue and re-run this script (it will resume from where it stopped)"
        Write-Info "State is saved in: $STATE_FILE_PATH"
        exit 1
    }
}

# Run
Main
