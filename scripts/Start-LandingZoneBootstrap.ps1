#Requires -Version 7.0
<#
.SYNOPSIS
    Landing Zone Phase 0 Bootloader — Complete OIDC + GitHub + Azure + TFC orchestration

.DESCRIPTION
    Single entry point for bootstrapping a landing zone deployment. This script:

    PHASE 0 (LOCAL, THIS SCRIPT):
      1. Validate/install CLIs (az, gh, git, terraform)
      2. Authenticate to Azure, GitHub, and Terraform Cloud
      3. Create Entra apps and service principals (with proper least-privilege)
      4. Create federated OIDC credentials (scoped to branches/environments)
      5. Set up GitHub secrets and variables
      6. Create GitHub environments with proper protection
      7. Validate Terraform Cloud workspace exists
      8. Generate deployment report
      9. Create a ready-to-merge PR with all generated files

    PHASE 0.1 (WORKFLOW, DELEGATED TO workflow-010):
      - terraform init (TFC backend)
      - Create workload resource groups
      - Validate OIDC connectivity
      - Run first terraform plan

    IDEMPOTENT: Safe to re-run. State is tracked in .lz-bootloader-state.json

    SINGLE USER: Designed for admin/owner bootstrapping. Prompts for authentication.

    LANDING ZONE: Creates proper separation between human OAuth and CI/CD OIDC,
                  with layered service principals (Main/Dev/Prod).

.EXAMPLE
    .\scripts\Start-LandingZoneBootstrap.ps1

.EXAMPLE
    .\scripts\Start-LandingZoneBootstrap.ps1 -SkipToolValidation -SkipAzureSetup

.EXAMPLE
    # Customer engagement: org-owned fork, wizard-exported config, team-gated
    # environments. backend.type in lz-config.json decides whether the TFC
    # phases run (azurerm skips them and sets TERRAFORM_CLOUD_ENABLED=false).
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

    # Explicit state-backend override: 'hcp-terraform' (HCP Terraform / TFC)
    # or 'azurerm' (Azure Storage, AAD-auth). Outranks the lz-config.json
    # backend.type. With 'azurerm' the TFC auth phase (2.3) and the TFC
    # org/workspace/TF_API_TOKEN phase (7) are skipped and
    # TERRAFORM_CLOUD_ENABLED is set to 'false'.
    [ValidateSet('', 'hcp-terraform', 'azurerm')]
    [string]$Backend = '',

    # Required reviewers for the dev/prod/hub GitHub environments: user logins
    # and/or 'org/team' slugs. Default (empty) falls back to the bootstrapping
    # operator — SELF-APPROVAL in a single-owner repo, warned about loudly and
    # unacceptable for customer engagements.
    [string[]]$EnvironmentReviewers = @(),

    # Sandbox subscription ID. When supplied, the deploying main-layer SP
    # (main-prod, or main-dev for Dev-only deployments) is
    # granted Role Based Access Control Administrator scoped to this
    # subscription so platform-management can write the sandbox-cleanup
    # Contributor assignment. Without it, that apply fails AuthorizationFailed.
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

function Confirm-Auth-TerraformCloud {
    Write-Section "2.3" "Terraform Cloud (Optional)"

    Write-Step "Checking Terraform Cloud configuration..."

    $tfc = @{
        organization = ""
        workspace    = ""
        token        = ""
    }

    # Check if .terraformrc exists
    $terraformrc = if ($IsWindows) {
        Join-Path $env:APPDATA 'terraform' '.terraformrc'
    } else {
        Join-Path $env:HOME '.terraformrc'
    }

    if (Test-Path $terraformrc) {
        $content = Get-Content $terraformrc -Raw
        if ($content -match 'app\.terraform\.io') {
            Write-OK "Terraform Cloud credentials found in $terraformrc"
            $tfc['token_source'] = '.terraformrc'
        }
    }

    return $tfc
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    CONFIGURATION GATHERING                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝

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

    # backend.type → backend_type; hcpTerraform block → TFC org + workspace
    if (-not $State.ContainsKey('backend_type') -and
        $config.ContainsKey('backend') -and $config['backend'].ContainsKey('type')) {
        $backendCfg = $config['backend']
        $State['backend_type'] = $backendCfg['type']
        Write-OK "State backend (from config): $($State['backend_type'])"

        if ($State['backend_type'] -eq 'hcp-terraform' -and $backendCfg.ContainsKey('hcpTerraform')) {
            $hcp = $backendCfg['hcpTerraform']
            if (-not $State.ContainsKey('tfc_organization') -and $hcp.ContainsKey('organization')) {
                $State['tfc_organization'] = $hcp['organization']
                Write-OK "TFC organization (from config): $($State['tfc_organization'])"
            }
            if (-not $State.ContainsKey('tfc_workspace')) {
                # Schema convention: workspaces are {workspacePrefix}-{layer};
                # this legacy script manages the single 'landing-zone' layer.
                $wsPrefix = if ($hcp.ContainsKey('workspacePrefix') -and
                    -not [string]::IsNullOrWhiteSpace($hcp['workspacePrefix'])) {
                    $hcp['workspacePrefix']
                } elseif ($State.ContainsKey('org_prefix')) {
                    $State['org_prefix']
                } else {
                    ''
                }
                $State['tfc_workspace'] = if ($wsPrefix) { "$wsPrefix-landing-zone" } else { 'landing-zone' }
                Write-OK "TFC workspace (from config): $($State['tfc_workspace'])"
            }
        }
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

    # State backend (seeded by -Backend or -ConfigPath; HCP Terraform remains
    # the recorded default backend decision)
    if (-not $State.ContainsKey('backend_type')) {
        Write-Host ""
        Write-Host "  Which Terraform state backend does this deployment use?" -ForegroundColor Cyan
        Write-Host "  [1] HCP Terraform / Terraform Cloud (default)"
        Write-Host "  [2] Azure Storage (azurerm, AAD-auth)"
        $backend_choice = Read-Host "  Select [1-2]"

        $State['backend_type'] = if ($backend_choice -eq '2') { 'azurerm' } else { 'hcp-terraform' }
    }
    Write-OK "State backend: $($State['backend_type'])"

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

function New-LzServicePrincipal {
    param(
        [string]$Layer,
        [string]$Environment,
        [string]$SubscriptionId,
        [hashtable]$State
    )

    $orgPrefix = $State['org_prefix']
    $displayName = "sp-terraform-$layer-$environment-$orgPrefix"

    # Check if exists
    $existing = az ad app list --display-name $displayName --query "[0].appId" -o tsv 2>$null
    Assert-LastExitCode "az ad app list --display-name $displayName"
    if ([string]::IsNullOrWhiteSpace($existing)) {
        Write-Step "Creating app registration: $displayName"
        $appId = (az ad app create --display-name $displayName --output json | ConvertFrom-Json).appId
        Assert-LastExitCode "az ad app create --display-name $displayName"
        Write-OK "Created app registration"
    } else {
        $appId = $existing
        Write-OK "Using existing app registration"
    }

    # Create service principal if needed
    $spCheck = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv 2>$null
    Assert-LastExitCode "az ad sp list --filter appId eq $appId"
    if ([string]::IsNullOrWhiteSpace($spCheck)) {
        Write-Step "Creating service principal..."
        az ad sp create --id $appId --output none 2>$null
        Assert-LastExitCode "az ad sp create --id $appId"
        Start-Sleep -Seconds 5  # Wait for replication
        Write-OK "Created service principal"
    }

    # Get object ID for RBAC
    $spObjId = az ad sp show --id $appId --query id -o tsv 2>$null
    Assert-LastExitCode "az ad sp show --id $appId"

    # Assign roles based on layer (least privilege):
    #  - plan:     Reader + Storage Blob Data Reader — the PR-triggered plan
    #              identity must never mutate
    #  - main:     Contributor + Storage Blob Data Contributor
    #  - dev/prod: the above + Role Based Access Control Administrator
    #              (replaces User Access Administrator; constrain the assignment
    #              with delegation conditions — restrict which roles it may
    #              assign and to which principal types — before production use)
    #
    # The Storage Blob Data roles are the data plane: the state account has
    # shared_access_key_enabled = false and every backend.hcl sets
    # use_azuread_auth = true, so state reads/writes go over AAD. Contributor
    # and Reader alone stop at the management plane and 403 on the blobs.
    if ($Layer -eq 'plan') {
        # No data-plane write: PR plans run with -lock=false and can never
        # mutate state.
        $roles = @("Reader", "Storage Blob Data Reader")
    } else {
        $roles = @("Contributor", "Storage Blob Data Contributor")
        if ($Layer -ne 'main') {
            $roles += "Role Based Access Control Administrator"
        }
    }

    foreach ($role in $roles) {
        $existing = az role assignment list `
            --assignee-object-id $spObjId `
            --role $role `
            --scope "/subscriptions/$SubscriptionId" `
            --query "[0].id" -o tsv 2>$null
        Assert-LastExitCode "az role assignment list (role '$role' on $displayName)"

        if ([string]::IsNullOrWhiteSpace($existing)) {
            Write-Step "Assigning role: $role"
            az role assignment create `
                --role $role `
                --assignee-object-id $spObjId `
                --assignee-principal-type ServicePrincipal `
                --scope "/subscriptions/$SubscriptionId" `
                --output none 2>$null
            Assert-LastExitCode "az role assignment create (role '$role' on $displayName)"
            Write-OK "Assigned $role"
        }
    }

    # Validate no Owner role
    $owner = az role assignment list `
        --assignee-object-id $spObjId `
        --query "[?roleDefinitionName=='Owner']" `
        --output json 2>$null | ConvertFrom-Json
    Assert-LastExitCode "az role assignment list (Owner check on $displayName)"

    if (($owner | Measure-Object).Count -gt 0) {
        Write-Critical "Service principal has Owner role! This violates least-privilege."
        throw "Owner role must be removed before proceeding"
    }

    return @{
        appId  = $appId
        spObjId = $spObjId
        displayName = $displayName
        roles = $roles
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

    Write-Section "4" "Azure OIDC Service Principals & Federated Credentials"

    Write-Critical "RESOURCE CREATION: This section will create Azure resources (Entra apps, SPs, RBAC roles)"
    Write-Info "Estimated resources:"
    Write-Info "  - 4 app registrations (main, plan, dev, prod)"
    Write-Info "  - 4 service principals"
    Write-Info "  - 8+ federated credentials (OIDC tokens)"
    Write-Info "  - 4+ RBAC role assignments"
    Write-Info ""
    $confirm = Read-Host "  Type 'CREATE' to proceed, or press ENTER to skip"

    if ($confirm -ne 'CREATE') {
        Write-Warn "Skipped Azure OIDC setup"
        return @{}
    }

    $sps = @{}

    # Create three SPs: main, dev, prod
    foreach ($layer in @('main', 'dev', 'prod')) {
        foreach ($env in $State['environments']) {
            $key = "$layer-$env"
            Write-Step "Setting up: $key"
            $sps[$key] = New-LzServicePrincipal -Layer $layer -Environment $env -SubscriptionId $SubscriptionId -State $State
        }
    }

    # Split identities: a dedicated Reader-only SP is the ONLY identity bound to
    # the pull_request OIDC subject, so PR-triggered plans can read but never
    # mutate Azure. The Contributor SP keeps main-branch and environment subjects.
    Write-Step "Setting up: plan (Reader-only PR plan identity)"
    $sps['plan'] = New-LzServicePrincipal -Layer 'plan' -Environment 'ci' -SubscriptionId $SubscriptionId -State $State

    # Create federated credentials for each layer
    foreach ($layer in @('main', 'dev', 'prod')) {
        foreach ($env in $State['environments']) {
            $key = "$layer-$env"
            $sp = $sps[$key]

            Write-Step "Creating federated credentials for: $key"

            switch ($layer) {
                'main' {
                    # Contributor SP: bound to main-branch pushes (terraform-apply.yml)
                    # and to the deployment environments (dev/prod/hub). It is
                    # deliberately NOT bound to the pull_request subject — PR-triggered
                    # plans authenticate as the Reader-only 'plan' SP instead.
                    Add-OidcFederatedCredential -AppId $sp.appId `
                        -Name "github-main-branch" `
                        -Subject "repo:$GithubOwner/$RepoName`:ref:refs/heads/main"

                    foreach ($envName in @('dev', 'prod', 'hub')) {
                        Add-OidcFederatedCredential -AppId $sp.appId `
                            -Name "github-environment-$envName" `
                            -Subject "repo:$GithubOwner/$RepoName`:environment:$envName"
                    }
                }
                'dev' {
                    # Dev runs on environment:dev
                    Add-OidcFederatedCredential -AppId $sp.appId `
                        -Name "github-environment-dev" `
                        -Subject "repo:$GithubOwner/$RepoName`:environment:dev"
                }
                'prod' {
                    # Prod runs on environment:prod and environment:hub (approval gate)
                    Add-OidcFederatedCredential -AppId $sp.appId `
                        -Name "github-environment-prod" `
                        -Subject "repo:$GithubOwner/$RepoName`:environment:prod"

                    Add-OidcFederatedCredential -AppId $sp.appId `
                        -Name "github-environment-hub" `
                        -Subject "repo:$GithubOwner/$RepoName`:environment:hub"
                }
            }
        }
    }

    # Reader-only plan SP: the ONLY identity holding the pull_request subject.
    Write-Step "Creating federated credential for: plan (pull_request)"
    Add-OidcFederatedCredential -AppId $sps['plan'].appId `
        -Name "github-pull-request" `
        -Subject "repo:$GithubOwner/$RepoName`:pull_request"

    # platform-management writes a Contributor assignment into the sandbox
    # subscription (sandbox-cleanup automation), which needs
    # Microsoft.Authorization/roleAssignments/write there. Grant the deploying
    # main-layer SP (published as AZURE_CLIENT_ID) RBAC Administrator scoped to
    # the sandbox subscription only — never Owner/UAA, and never in the
    # management subscription. The key is per selected environment: prefer
    # main-prod, fall back to main-dev (Dev-only deployments no longer create
    # a main-prod SP) — the SAME resolution Set-GitHubSecrets uses, so the
    # grant lands on the identity the workflows actually authenticate as.
    if (-not [string]::IsNullOrWhiteSpace($SandboxSubscriptionId)) {
        $mainSpKey = if ($sps.ContainsKey('main-prod')) { 'main-prod' } else { 'main-dev' }
        Write-Step "Granting sandbox-subscription RBAC Administrator to $mainSpKey SP"
        $mainObjId = az ad sp show --id $sps[$mainSpKey].appId --query id -o tsv 2>$null
        Assert-LastExitCode "az ad sp show --id $($sps[$mainSpKey].appId)"

        $existingSandboxGrant = az role assignment list `
            --assignee-object-id $mainObjId `
            --role "Role Based Access Control Administrator" `
            --scope "/subscriptions/$SandboxSubscriptionId" `
            --query "[0].id" -o tsv 2>$null
        Assert-LastExitCode "az role assignment list (sandbox RBAC grant)"

        if ([string]::IsNullOrWhiteSpace($existingSandboxGrant)) {
            az role assignment create `
                --role "Role Based Access Control Administrator" `
                --assignee-object-id $mainObjId `
                --assignee-principal-type ServicePrincipal `
                --scope "/subscriptions/$SandboxSubscriptionId" `
                --output none 2>$null
            Assert-LastExitCode "az role assignment create (sandbox RBAC grant)"
            Write-OK "Granted RBAC Administrator on sandbox subscription"
        } else {
            Write-OK "Sandbox RBAC Administrator grant already present"
        }
    } elseif ($SandboxRbacSkipRequested) {
        Write-Warn "Sandbox RBAC grant deliberately skipped (-SkipSandboxRbac): platform-management's sandbox-cleanup role assignment will fail (AuthorizationFailed) until the deploying SP is granted RBAC Administrator in the sandbox subscription"
    } else {
        Write-Warn "No -SandboxSubscriptionId supplied: platform-management's sandbox-cleanup role assignment will fail (AuthorizationFailed) until the deploying SP is granted RBAC Administrator in the sandbox subscription"
    }

    Write-OK "Azure OIDC setup complete"
    $State['azure_sps'] = $sps
    Save-BootloaderState $State

    return $sps
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                   GITHUB SECRETS & VARIABLES                            ║
# ╚══════════════════════════════════════════════════════════════════════════╝

function Set-GitHubSecrets {
    param(
        [hashtable]$State,
        [string]$GithubOwner,
        [string]$RepoName,
        [hashtable]$ServicePrincipals
    )

    Write-Section "5" "GitHub Secrets & Variables Configuration"

    $repo = "$GithubOwner/$RepoName"

    # Repo-level secrets (used by main branch jobs). The main-layer SP is
    # keyed per selected environment: prefer main-prod, fall back to main-dev
    # (Dev-only deployments no longer create a main-prod SP).
    $mainSpKey = if ($ServicePrincipals.ContainsKey('main-prod')) { 'main-prod' } else { 'main-dev' }
    $mainSp = $ServicePrincipals[$mainSpKey]
    Write-Step "Setting repo-level secrets (used by main branch; deploying SP: $mainSpKey)..."

    foreach ($secret in @(
        @{ Name = 'AZURE_TENANT_ID';       Value = $State['tenant_id'] },
        @{ Name = 'AZURE_SUBSCRIPTION_ID'; Value = $State['subscription_id'] },
        @{ Name = 'AZURE_CLIENT_ID';       Value = $mainSp.appId }
    )) {
        Write-Step "Setting secret: $($secret.Name)"
        $secret.Value | gh secret set $secret.Name --repo $repo 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Secret set: $($secret.Name)"
        } else {
            Write-Warn "Could not set secret $($secret.Name) via CLI"
        }
    }

    # Reader-only plan SP client id, for PR-triggered workflows (pull_request
    # OIDC subject is bound only to this identity).
    if ($ServicePrincipals.ContainsKey('plan')) {
        Write-Step "Setting secret: AZURE_PLAN_CLIENT_ID (Reader-only plan SP)"
        $ServicePrincipals['plan'].appId | gh secret set 'AZURE_PLAN_CLIENT_ID' --repo $repo 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Secret set: AZURE_PLAN_CLIENT_ID"
        } else {
            Write-Warn "Could not set secret AZURE_PLAN_CLIENT_ID via CLI"
        }
    }

    # Environment-scoped secrets (override repo-level for specific environments)
    foreach ($env in $State['environments']) {
        if ($env -ne 'prod') { continue }  # Only prod needs environment secrets for now

        $sp = $ServicePrincipals["prod-$env"]
        Write-Step "Setting environment-scoped secrets for: $env"

        $sp.appId | gh secret set "AZURE_CLIENT_ID" --repo $repo --env $env 2>&1 | Out-Null
        Write-OK "Set env secret: AZURE_CLIENT_ID (env:$env)"
    }

    # GitHub Variables. TERRAFORM_CLOUD_ENABLED follows the backend choice:
    # 'true' only for hcp-terraform; azurerm state lives in Azure Storage.
    Write-Step "Setting GitHub variables..."

    $tfcEnabled = if ($State.ContainsKey('backend_type') -and $State['backend_type'] -eq 'azurerm') { 'false' } else { 'true' }

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

    foreach ($env in $State['environments']) {
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

function Setup-TerraformCloud {
    param(
        [hashtable]$State,
        [string]$GithubOwner,
        [string]$RepoName
    )

    Write-Section "7" "Terraform Cloud Configuration"

    # Honor the backend decision: azurerm state lives in Azure Storage
    # (AAD-auth) — no TFC organization, workspace, or TF_API_TOKEN is needed.
    if ($State.ContainsKey('backend_type') -and $State['backend_type'] -eq 'azurerm') {
        Write-OK "Skipped: azurerm backend selected — state is in Azure Storage, no TFC org/workspace/TF_API_TOKEN required"
        return
    }

    $repo = "$GithubOwner/$RepoName"

    # Prompt for TFC organization (seeded by -ConfigPath when supplied)
    if (-not $State.ContainsKey('tfc_organization')) {
        $tfc_org = Read-Host "  Terraform Cloud organization name (e.g., my-company)"
        if ([string]::IsNullOrEmpty($tfc_org)) {
            Write-Warn "Skipping TFC setup (you can configure manually later)"
            return
        }
        $State['tfc_organization'] = $tfc_org
    }

    $tfc_org = $State['tfc_organization']

    # Workspace name (seeded by -ConfigPath; the old hardcoded 'landing-zone'
    # remains the interactive default only)
    if (-not $State.ContainsKey('tfc_workspace')) {
        $workspace_input = Read-Host "  Terraform Cloud workspace name (default: landing-zone)"
        if ([string]::IsNullOrEmpty($workspace_input)) { $workspace_input = 'landing-zone' }
        $State['tfc_workspace'] = $workspace_input
    }
    $workspace = $State['tfc_workspace']

    Write-Step "TFC Organization: $tfc_org"
    Write-Step "TFC Workspace: $workspace"

    # Prompt for API token
    if (-not $State.ContainsKey('tfc_token_set')) {
        Write-Manual "You need a Terraform Cloud API token."
        Write-Info "  1. Log in to app.terraform.io"
        Write-Info "  2. Go to Settings → Tokens"
        Write-Info "  3. Create a new API token"
        Write-Info "  4. Paste it below (input will be hidden)"
        Write-Host ""

        $token_secure = Read-Host "  Paste your TFC API token" -AsSecureString
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($token_secure))

        if ([string]::IsNullOrEmpty($token)) {
            Write-Warn "No token provided - skipping TFC setup"
            return
        }

        # Set GitHub secret for TFC token
        Write-Step "Storing TFC API token in GitHub secrets..."
        $token | gh secret set TF_API_TOKEN --repo $repo 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-OK "TFC API token stored securely"
        } else {
            Write-Warn "Could not store TFC token in GitHub"
        }

        $State['tfc_token_set'] = $true
    }

    # Set GitHub variables for TFC
    Write-Step "Setting TFC configuration variables..."
    gh variable set TF_CLOUD_ORGANIZATION --repo $repo --body $tfc_org 2>&1 | Out-Null
    gh variable set TF_CLOUD_WORKSPACE --repo $repo --body $workspace 2>&1 | Out-Null

    Write-OK "Terraform Cloud configured"
    Write-Info "Organization: $tfc_org"
    Write-Info "Workspace: $workspace"
    Write-Info "Next: Workflow 010 will initialize TFC backend"

    Save-BootloaderState $State
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                    BOOTSTRAP REPORT & PR                                ║
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

    # Precompute dynamic sections: the SP inventory follows the selected
    # environments (dev-only no longer implies *-prod keys), and the backend
    # section follows the backend_type decision.
    $spRows = ''
    if ($State.ContainsKey('azure_sps') -and $State['azure_sps'].Count -gt 0) {
        foreach ($spKey in ($State['azure_sps'].Keys | Sort-Object)) {
            $spNote = if ($spKey -eq 'plan') { 'plan (Reader-only, pull_request)' } else { $spKey }
            $spRows += "| $spNote | $($State['azure_sps'][$spKey]['appId']) | ✓ Created |`n"
        }
    } else {
        $spRows = "| (none — Azure OIDC setup was skipped) | — | — |`n"
    }
    $spRows = $spRows.TrimEnd("`n")

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
| Backend | hcp-terraform |
| Organization | $($State['tfc_organization'] ?? 'Not configured') |
| Workspace | $($State['tfc_workspace'] ?? 'landing-zone') |
| API Token | Stored in GitHub secret: TF_API_TOKEN |
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
| Region | $($State['region']) ($($State['region_code'])) |
| Repository | $($State['github_owner'])/$($State['repo_name']) |
| State Backend | $($State['backend_type'] ?? 'hcp-terraform') |
| Azure Tenant | $($State['tenant_id']) |
| Azure Subscription | $($State['subscription_id']) |

## OIDC Service Principals

| Identity (layer-environment) | App ID | Status |
|------------------------------|--------|--------|
$spRows

## GitHub Configuration

- ✓ Repository Secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
- ✓ GitHub Variables: Org prefix, region, TF version, etc.
- ✓ Environments: $($State['environments'] -join ', '), hub
- ✓ Federated Credentials: OIDC tokens scoped per layer/environment

## State Backend

$backendSection

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

- All service principals use OIDC federated credentials (no secrets stored)
- Least-privilege RBAC: Contributor for main; Contributor + Role Based Access Control Administrator (constrain with delegation conditions) for dev/prod; Reader-only for the plan SP
- Contributor (main) SP scoped to main-branch pushes and dev/prod/hub environments (cannot deploy from other branches/forks)
- pull_request OIDC subject bound ONLY to the Reader-only plan SP (PR plans cannot mutate Azure)
- No Owner or User Access Administrator roles assigned to any service principal
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

- Created OIDC service principals (main/dev/prod)
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

        # Phase 2.3 (runs after Phase 3 by design): the TFC auth check only
        # applies when the hcp-terraform backend is selected
        if ($state['backend_type'] -eq 'hcp-terraform') {
            Confirm-Auth-TerraformCloud
            Mark-StepComplete $state "tfc-auth"
        } else {
            Write-Info "Skipping Terraform Cloud auth check (backend: $($state['backend_type']))"
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
        # key then calling .Count on $null would fail.
        if ($state.ContainsKey('azure_sps') -and $state['azure_sps'].Count -gt 0) {
            Set-GitHubSecrets `
                -State $state `
                -GithubOwner $repoOwner `
                -RepoName $repoName `
                -ServicePrincipals $state['azure_sps']

            Mark-StepComplete $state "github-secrets"
        }

        # Phase 6: GitHub environments
        Setup-GitHub-Environments `
            -GithubOwner $repoOwner `
            -RepoName $repoName `
            -State $state `
            -EnvironmentReviewers $EnvironmentReviewers

        Mark-StepComplete $state "github-environments"

        # Phase 7: Terraform Cloud (skips itself when backend_type=azurerm)
        Setup-TerraformCloud `
            -State $state `
            -GithubOwner $repoOwner `
            -RepoName $repoName

        Mark-StepComplete $state "tfc-setup"

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
        if ($state['backend_type'] -eq 'azurerm') {
            Write-OK "✓ State backend: azurerm (Terraform Cloud phases skipped)"
        } else {
            Write-OK "✓ Terraform Cloud configured"
        }
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
