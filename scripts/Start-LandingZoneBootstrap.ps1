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
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipToolValidation,
    [switch]$SkipAzureSetup,
    [string]$ReportDirectory = ".reports/bootstrap",
    [string]$StateFile = ".lz-bootloader-state.json",

    # Sandbox subscription ID. When supplied, the deploying SP (main-prod) is
    # granted Role Based Access Control Administrator scoped to this
    # subscription so platform-management can write the sandbox-cleanup
    # Contributor assignment. Without it, that apply fails AuthorizationFailed.
    [string]$SandboxSubscriptionId = ''
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

# Landing Zone naming convention
$LZ_APP_PATTERN = "sp-terraform-{layer}-{environment}"

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
    $account = az account show --output json 2>&1
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

    # Environment (dev/prod or both)
    if (-not $State.ContainsKey('environments')) {
        Write-Host ""
        Write-Host "  Which environments will you deploy to?" -ForegroundColor Cyan
        Write-Host "  [1] Dev only (rapid iteration)"
        Write-Host "  [2] Prod only (single tier)"
        Write-Host "  [3] Both Dev and Prod (full layering)"
        $env_choice = Read-Host "  Select [1-3]"

        $envs = @('dev', 'prod')
        $State['environments'] = if ($env_choice -eq '2') { @('prod') } else { $envs }
    }
    Write-OK "Environments: $($State['environments'] -join ', ')"

    # Region
    if (-not $State.ContainsKey('region')) {
        $State['region'] = 'eastus'
        $State['region_code'] = 'eus'
    }
    Write-OK "Region: $($State['region']) ($($State['region_code']))"

    # Repository name
    if (-not $State.ContainsKey('repo_name')) {
        $repo_name = Read-Host "  GitHub repository name (default: HCW-Demo-LZDeployment)"
        if ([string]::IsNullOrEmpty($repo_name)) { $repo_name = 'HCW-Demo-LZDeployment' }
        $State['repo_name'] = $repo_name
    }
    Write-OK "Repository: $($State['repo_name'])"

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
        [string]$SandboxSubscriptionId = ''
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
    # SP (main-prod, published as AZURE_CLIENT_ID) RBAC Administrator scoped to
    # the sandbox subscription only — never Owner/UAA, and never in the
    # management subscription.
    if (-not [string]::IsNullOrWhiteSpace($SandboxSubscriptionId)) {
        Write-Step "Granting sandbox-subscription RBAC Administrator to main-prod SP"
        $mainObjId = az ad sp show --id $sps['main-prod'].appId --query id -o tsv 2>$null
        Assert-LastExitCode "az ad sp show --id $($sps['main-prod'].appId)"

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

    # Repo-level secrets (used by main branch jobs)
    $mainSp = $ServicePrincipals['main-prod']
    Write-Step "Setting repo-level secrets (used by main branch)..."

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

    # GitHub Variables
    Write-Step "Setting GitHub variables..."

    $variables = @{
        'AZURE_REGION'            = $State['region']
        'AZURE_REGION_CODE'       = $State['region_code']
        'ORG_PREFIX'              = $State['org_prefix']
        'TF_VERSION'              = '1.9'
        'TERRAFORM_CLOUD_ENABLED' = 'true'
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
        [hashtable]$State
    )

    Write-Section "6" "GitHub Environments"

    $repo = "$GithubOwner/$RepoName"

    # Protection payload sent with every environment PUT:
    #  - reviewers: the bootstrapping operator, resolved at runtime. A single
    #    reviewer means self-approval in a single-owner repo — replace with a
    #    Team object (@{ type = 'Team'; id = <numeric-team-id> }) once one
    #    exists, but an explicit human gate always beats an empty one.
    #  - deployment_branch_policy: restrict deployments to protected branches.
    Write-Step "Resolving bootstrap operator for environment approval gate"
    $reviewerId = [int](gh api user --jq '.id')
    Assert-LastExitCode "gh api user (resolve reviewer id)"
    $reviewerLogin = gh api user --jq '.login'
    Assert-LastExitCode "gh api user (resolve reviewer login)"
    Write-OK "Environment reviewer: $reviewerLogin ($reviewerId)"

    $protectionPayload = @{
        reviewers                = @(
            @{ type = 'User'; id = $reviewerId }
        )
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
    Write-Info "      (gated on $reviewerLogin; swap in a Team reviewer when one exists)"
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

    $repo = "$GithubOwner/$RepoName"

    # Prompt for TFC organization
    if (-not $State.ContainsKey('tfc_organization')) {
        $tfc_org = Read-Host "  Terraform Cloud organization name (e.g., my-company)"
        if ([string]::IsNullOrEmpty($tfc_org)) {
            Write-Warn "Skipping TFC setup (you can configure manually later)"
            return
        }
        $State['tfc_organization'] = $tfc_org
    }

    $tfc_org = $State['tfc_organization']
    $workspace = "landing-zone"  # Standard name

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
| Repository | $($State['repo_name']) |
| Azure Tenant | $($State['tenant_id']) |
| Azure Subscription | $($State['subscription_id']) |

## OIDC Service Principals

| Layer | Environment | App ID | Status |
|-------|-------------|--------|--------|
| main | prod | $($State['azure_sps']['main-prod'].appId) | ✓ Created |
| plan | ci (Reader-only, pull_request) | $($State['azure_sps']['plan'].appId) | ✓ Created |
| dev | $($State['environments'] -join ', ') | $($State['azure_sps']['dev-prod'].appId) | ✓ Created |
| prod | $($State['environments'] -join ', ') | $($State['azure_sps']['prod-prod'].appId) | ✓ Created |

## GitHub Configuration

- ✓ Repository Secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
- ✓ GitHub Variables: Org prefix, region, TF version, etc.
- ✓ Environments: dev, prod, hub
- ✓ Federated Credentials: OIDC tokens scoped per layer/environment

## Terraform Cloud

| Setting | Value |
|---------|-------|
| Organization | $($State['tfc_organization'] ?? 'Not configured') |
| Workspace | landing-zone |
| API Token | Stored in GitHub secret: TF_API_TOKEN |

## Next Steps (Workflow 010)

1. ✓ Phase 0 (THIS SCRIPT): Local bootstrap complete
2. ⏭ Phase 0.1 (WORKFLOW 010): Run on next PR/commit
   - Initialize Terraform with TFC backend
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

    $repo = "$GithubOwner/$RepoName"

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
- Set up Terraform Cloud integration

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
- Terraform Cloud integration enabled

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

        Confirm-Auth-TerraformCloud
        Mark-StepComplete $state "tfc-auth"

        # Phase 3: Configuration
        Gather-DeploymentConfig $state
        Mark-StepComplete $state "config-gathered"

        # Phase 4: Azure OIDC setup
        if (-not $SkipAzureSetup) {
            $sps = Setup-Azure-OIDC `
                -State $state `
                -SubscriptionId $state['subscription_id'] `
                -TenantId $state['tenant_id'] `
                -GithubOwner $ghUser `
                -RepoName $state['repo_name'] `
                -SandboxSubscriptionId $SandboxSubscriptionId

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
                -GithubOwner $ghUser `
                -RepoName $state['repo_name'] `
                -ServicePrincipals $state['azure_sps']

            Mark-StepComplete $state "github-secrets"
        }

        # Phase 6: GitHub environments
        Setup-GitHub-Environments `
            -GithubOwner $ghUser `
            -RepoName $state['repo_name'] `
            -State $state

        Mark-StepComplete $state "github-environments"

        # Phase 7: Terraform Cloud
        Setup-TerraformCloud `
            -State $state `
            -GithubOwner $ghUser `
            -RepoName $state['repo_name']

        Mark-StepComplete $state "tfc-setup"

        # Phase 8: Report
        $reportPath = Generate-BootstrapReport -State $state -ReportDir $ReportDirectory
        Mark-StepComplete $state "report-generated"

        # Phase 9: PR
        Create-BootstrapPR -GithubOwner $ghUser -RepoName $state['repo_name']

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
        Write-OK "✓ Terraform Cloud configured"
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
