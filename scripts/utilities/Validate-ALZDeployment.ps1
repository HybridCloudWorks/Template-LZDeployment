<#
.SYNOPSIS
Azure Landing Zone Pre-Flight Validation Script
.DESCRIPTION
Comprehensive pre-deployment validation checks for ALZ deployments.
Validates Terraform configuration, Azure environment, OIDC federation, GitHub setup, and resource quotas.
.PARAMETER TerraformPath
Path to Terraform configuration directory
.PARAMETER SubscriptionId
Azure subscription ID for quota validation
.PARAMETER GitHubRepo
GitHub repository in format owner/repo
.PARAMETER OutputFormat
Output format: json, html, or text (default: text)
.EXAMPLE
.\Validate-ALZDeployment.ps1 -TerraformPath "./terraform/live/myorg" -SubscriptionId "xxxx-xxxx" -GitHubRepo "myorg/alz-deployment"
.NOTES
Version: 1.0
Author: ALZ Operations Team
Date: 2026-06-28
Requires: Az.Accounts, Az.Subscription, terraform CLI
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TerraformPath,

    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$false)]
    [string]$GitHubRepo,

    [Parameter(Mandatory=$false)]
    [ValidateSet("json", "html", "text")]
    [string]$OutputFormat = "text"
)

# Import config
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Get-AlzConfig.ps1")

class ValidationResult {
    [string]$Category
    [string]$Check
    [bool]$Passed
    [string]$Message
    [string]$Severity  # Critical, Warning, Info
    [string]$Remediation
}

$validationResults = @()

# ============================================================================
# TERRAFORM VALIDATION
# ============================================================================
Write-Host "🔍 Validating Terraform Configuration..." -ForegroundColor Cyan

# Check Terraform CLI installed
$terraformExe = Get-Command terraform -ErrorAction SilentlyContinue
if (-not $terraformExe) {
    $validationResults += [ValidationResult]@{
        Category    = "Terraform"
        Check       = "Terraform CLI installed"
        Passed      = $false
        Message     = "Terraform CLI not found in PATH"
        Severity    = "Critical"
        Remediation = "Install Terraform: https://www.terraform.io/downloads"
    }
} else {
    $validationResults += [ValidationResult]@{
        Category    = "Terraform"
        Check       = "Terraform CLI installed"
        Passed      = $true
        Message     = "Terraform $(terraform version -json | ConvertFrom-Json).terraform_version found"
        Severity    = "Info"
    }
}

# Check Terraform directory exists
if (-not (Test-Path $TerraformPath)) {
    $validationResults += [ValidationResult]@{
        Category    = "Terraform"
        Check       = "Terraform directory exists"
        Passed      = $false
        Message     = "Terraform path not found: $TerraformPath"
        Severity    = "Critical"
        Remediation = "Create Terraform configuration in: $TerraformPath"
    }
} else {
    $validationResults += [ValidationResult]@{
        Category    = "Terraform"
        Check       = "Terraform directory exists"
        Passed      = $true
        Message     = "Found at: $TerraformPath"
        Severity    = "Info"
    }

    # Terraform format check
    Push-Location $TerraformPath
    try {
        $formatOutput = terraform fmt -check -recursive 2>&1
        if ($LASTEXITCODE -eq 0) {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Terraform code formatting"
                Passed      = $true
                Message     = "Code follows Terraform formatting standards"
                Severity    = "Info"
            }
        } else {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Terraform code formatting"
                Passed      = $false
                Message     = "Code formatting issues detected in: $($formatOutput -join ', ')"
                Severity    = "Warning"
                Remediation = "Run: terraform fmt -recursive"
            }
        }
    } catch {
        $validationResults += [ValidationResult]@{
            Category    = "Terraform"
            Check       = "Terraform format validation"
            Passed      = $false
            Message     = "Error checking format: $_"
            Severity    = "Critical"
        }
    }

    # Terraform validate
    try {
        $validateOutput = terraform validate 2>&1
        if ($LASTEXITCODE -eq 0) {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Terraform syntax validation"
                Passed      = $true
                Message     = "Configuration is syntactically valid"
                Severity    = "Info"
            }
        } else {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Terraform syntax validation"
                Passed      = $false
                Message     = "Validation errors: $validateOutput"
                Severity    = "Critical"
                Remediation = "Fix errors in Terraform configuration"
            }
        }
    } catch {
        $validationResults += [ValidationResult]@{
            Category    = "Terraform"
            Check       = "Terraform validation"
            Passed      = $false
            Message     = "Error validating: $_"
            Severity    = "Critical"
        }
    }

    # Check for required variables
    try {
        $varFileExists = Test-Path (Join-Path $TerraformPath "terraform.tfvars")
        if ($varFileExists) {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Variable file exists"
                Passed      = $true
                Message     = "terraform.tfvars file found"
                Severity    = "Info"
            }
        } else {
            $validationResults += [ValidationResult]@{
                Category    = "Terraform"
                Check       = "Variable file exists"
                Passed      = $false
                Message     = "terraform.tfvars not found"
                Severity    = "Warning"
                Remediation = "Create terraform.tfvars with required variables"
            }
        }
    } catch {
        Write-Host "Error checking variables: $_"
    }

    Pop-Location
}

# ============================================================================
# AZURE ENVIRONMENT VALIDATION
# ============================================================================
Write-Host "🔍 Validating Azure Environment..." -ForegroundColor Cyan

# Check Az CLI installed
$azExe = Get-Command az -ErrorAction SilentlyContinue
if (-not $azExe) {
    $validationResults += [ValidationResult]@{
        Category    = "Azure"
        Check       = "Azure CLI installed"
        Passed      = $false
        Message     = "Azure CLI not found in PATH"
        Severity    = "Critical"
        Remediation = "Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    }
} else {
    $validationResults += [ValidationResult]@{
        Category    = "Azure"
        Check       = "Azure CLI installed"
        Passed      = $true
        Message     = "Azure CLI found"
        Severity    = "Info"
    }

    # Check Azure authentication
    try {
        $azAccount = az account show --output json 2>&1 | ConvertFrom-Json -ErrorAction Stop
        $validationResults += [ValidationResult]@{
            Category    = "Azure"
            Check       = "Azure authentication"
            Passed      = $true
            Message     = "Authenticated as: $($azAccount.user.name)"
            Severity    = "Info"
        }

        # Check subscription exists (only the exit code matters here)
        az account show --subscription $SubscriptionId 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $validationResults += [ValidationResult]@{
                Category    = "Azure"
                Check       = "Subscription accessible"
                Passed      = $true
                Message     = "Subscription $SubscriptionId is accessible"
                Severity    = "Info"
            }
        } else {
            $validationResults += [ValidationResult]@{
                Category    = "Azure"
                Check       = "Subscription accessible"
                Passed      = $false
                Message     = "Cannot access subscription: $SubscriptionId"
                Severity    = "Critical"
                Remediation = "Verify subscription ID and permissions"
            }
        }
    } catch {
        $validationResults += [ValidationResult]@{
            Category    = "Azure"
            Check       = "Azure authentication"
            Passed      = $false
            Message     = "Not authenticated to Azure"
            Severity    = "Critical"
            Remediation = "Run: az login"
        }
    }
}

# ============================================================================
# AZURE QUOTAS & LIMITS VALIDATION
# ============================================================================
Write-Host "🔍 Validating Azure Quotas..." -ForegroundColor Cyan

try {
    $quotaOutput = az vm list-usage --subscription $SubscriptionId --output json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $quotas = $quotaOutput | ConvertFrom-Json -ErrorAction Stop

        # Check vCPU quota
        $vCpuQuota = $quotas | Where-Object { $_.name.value -eq "cores" }
        if ($vCpuQuota) {
            $percentUsed = ($vCpuQuota.currentValue / $vCpuQuota.limit) * 100
            if ($percentUsed -lt 80) {
                $validationResults += [ValidationResult]@{
                    Category    = "Azure Quotas"
                    Check       = "vCPU quota available"
                    Passed      = $true
                    Message     = "vCPU usage: $($vCpuQuota.currentValue)/$($vCpuQuota.limit) ($percentUsed.2f%)"
                    Severity    = "Info"
                }
            } else {
                $validationResults += [ValidationResult]@{
                    Category    = "Azure Quotas"
                    Check       = "vCPU quota available"
                    Passed      = $false
                    Message     = "vCPU quota near limit: $percentUsed.2f% used"
                    Severity    = "Warning"
                    Remediation = "Request quota increase in Azure Portal"
                }
            }
        }

        # Check storage accounts quota
        $storageQuota = $quotas | Where-Object { $_.name.value -eq "storageAccounts" }
        if ($storageQuota) {
            $percentUsed = ($storageQuota.currentValue / $storageQuota.limit) * 100
            if ($percentUsed -lt 80) {
                $validationResults += [ValidationResult]@{
                    Category    = "Azure Quotas"
                    Check       = "Storage account quota"
                    Passed      = $true
                    Message     = "Storage usage: $($storageQuota.currentValue)/$($storageQuota.limit)"
                    Severity    = "Info"
                }
            }
        }
    }
} catch {
    $validationResults += [ValidationResult]@{
        Category    = "Azure Quotas"
        Check       = "Quota validation"
        Passed      = $false
        Message     = "Error checking quotas: $_"
        Severity    = "Warning"
    }
}

# ============================================================================
# OIDC FEDERATION VALIDATION
# ============================================================================
Write-Host "🔍 Validating OIDC Federation..." -ForegroundColor Cyan

if ($GitHubRepo) {
    try {
        # Check if federated identity exists
        $oidcCheck = az identity federated-identity-credential list --resource-group "$($SubscriptionId.split('-')[0])-rg" 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

        if ($oidcCheck.Count -gt 0) {
            $validationResults += [ValidationResult]@{
                Category    = "OIDC"
                Check       = "Federated identity configured"
                Passed      = $true
                Message     = "Found $($oidcCheck.Count) federated identity credential(s)"
                Severity    = "Info"
            }
        } else {
            $validationResults += [ValidationResult]@{
                Category    = "OIDC"
                Check       = "Federated identity configured"
                Passed      = $false
                Message     = "No federated identities found"
                Severity    = "Warning"
                Remediation = "Configure GitHub OIDC federation in Azure Entra ID"
            }
        }
    } catch {
        $validationResults += [ValidationResult]@{
            Category    = "OIDC"
            Check       = "Federated identity check"
            Passed      = $false
            Message     = "Error checking OIDC: $_"
            Severity    = "Warning"
        }
    }
}

# ============================================================================
# GITHUB VALIDATION
# ============================================================================
Write-Host "🔍 Validating GitHub Setup..." -ForegroundColor Cyan

if ($GitHubRepo) {
    $ghExe = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghExe) {
        try {
            # Check GitHub CLI authentication (only the exit code matters here)
            gh auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $validationResults += [ValidationResult]@{
                    Category    = "GitHub"
                    Check       = "GitHub CLI authenticated"
                    Passed      = $true
                    Message     = "GitHub CLI is authenticated"
                    Severity    = "Info"
                }

                # Check if repo exists (only the exit code matters here)
                gh repo view $GitHubRepo 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $validationResults += [ValidationResult]@{
                        Category    = "GitHub"
                        Check       = "Repository exists"
                        Passed      = $true
                        Message     = "Repository $GitHubRepo found"
                        Severity    = "Info"
                    }

                    # Check for required secrets
                    $secrets = @("AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID")
                    foreach ($secret in $secrets) {
                        # A missing secret makes gh exit non-zero without throwing,
                        # so branch on the exit code (a catch block never fires here).
                        gh secret view $secret --repo $GitHubRepo 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            $validationResults += [ValidationResult]@{
                                Category    = "GitHub Secrets"
                                Check       = "Secret: $secret"
                                Passed      = $true
                                Message     = "Secret is configured"
                                Severity    = "Info"
                            }
                        } else {
                            $validationResults += [ValidationResult]@{
                                Category    = "GitHub Secrets"
                                Check       = "Secret: $secret"
                                Passed      = $false
                                Message     = "Secret not found"
                                Severity    = "Warning"
                                Remediation = "Add secret to GitHub: gh secret set $secret --repo $GitHubRepo"
                            }
                        }
                    }
                } else {
                    $validationResults += [ValidationResult]@{
                        Category    = "GitHub"
                        Check       = "Repository exists"
                        Passed      = $false
                        Message     = "Repository $GitHubRepo not found"
                        Severity    = "Critical"
                    }
                }
            } else {
                $validationResults += [ValidationResult]@{
                    Category    = "GitHub"
                    Check       = "GitHub CLI authenticated"
                    Passed      = $false
                    Message     = "GitHub CLI not authenticated"
                    Severity    = "Critical"
                    Remediation = "Run: gh auth login"
                }
            }
        } catch {
            $validationResults += [ValidationResult]@{
                Category    = "GitHub"
                Check       = "GitHub validation"
                Passed      = $false
                Message     = "Error validating GitHub: $_"
                Severity    = "Warning"
            }
        }
    } else {
        $validationResults += [ValidationResult]@{
            Category    = "GitHub"
            Check       = "GitHub CLI installed"
            Passed      = $false
            Message     = "GitHub CLI not found in PATH"
            Severity    = "Warning"
            Remediation = "Install GitHub CLI: https://cli.github.com"
        }
    }
}

# ============================================================================
# GENERATE REPORT
# ============================================================================
$failureCount = @($validationResults | Where-Object { -not $_.Passed }).Count
$criticalCount = @($validationResults | Where-Object { $_.Severity -eq "Critical" -and -not $_.Passed }).Count
$warningCount = @($validationResults | Where-Object { $_.Severity -eq "Warning" -and -not $_.Passed }).Count

Write-Host "`n" + "="*80
Write-Host "✅ ALZ PRE-FLIGHT VALIDATION REPORT" -ForegroundColor Green
Write-Host "="*80
Write-Host "Subscription: $SubscriptionId"
Write-Host "Terraform Path: $TerraformPath"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "="*80 + "`n"

# Summary
Write-Host "📊 SUMMARY:"
Write-Host "  Total Checks: $($validationResults.Count)"
Write-Host "  ✅ Passed: $(@($validationResults | Where-Object { $_.Passed }).Count)"
Write-Host "  ❌ Failed: $failureCount"
Write-Host "  ⚠️  Warnings: $warningCount"
Write-Host "  ❌ Critical: $criticalCount"
Write-Host ""

if ($criticalCount -gt 0) {
    Write-Host "🚨 CRITICAL ISSUES FOUND - DEPLOYMENT NOT RECOMMENDED" -ForegroundColor Red
} elseif ($warningCount -gt 0) {
    Write-Host "⚠️  WARNINGS FOUND - REVIEW BEFORE DEPLOYMENT" -ForegroundColor Yellow
} else {
    Write-Host "✅ ALL CHECKS PASSED - READY FOR DEPLOYMENT" -ForegroundColor Green
}

Write-Host ""

# Detailed results grouped by category
$categories = $validationResults | Group-Object -Property Category
foreach ($category in $categories) {
    Write-Host "━━ $($category.Name)" -ForegroundColor Cyan
    foreach ($result in $category.Group) {
        $symbol = if ($result.Passed) { "✅" } else { "❌" }
        Write-Host "  $symbol $($result.Check)"
        Write-Host "     → $($result.Message)"
        if (-not $result.Passed -and $result.Remediation) {
            Write-Host "     💡 $($result.Remediation)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

Write-Host "="*80 + "`n"

# Export report based on format
if ($OutputFormat -eq "json") {
    $jsonOutput = @{
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        summary = @{
            total = $validationResults.Count
            passed = @($validationResults | Where-Object { $_.Passed }).Count
            failed = $failureCount
            warnings = $warningCount
            critical = $criticalCount
        }
        results = $validationResults
    }
    $jsonOutput | ConvertTo-Json | Set-Content -Path "alz-validation-report.json"
    Write-Host "📄 JSON report saved to: alz-validation-report.json"
}

# Exit code based on critical issues
if ($criticalCount -gt 0) {
    exit 1
} else {
    exit 0
}
