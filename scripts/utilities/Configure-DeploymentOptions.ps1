# Azure Landing Zone - Deployment Options Configuration Script
# Helps configure optional security and compliance modules

<#
.SYNOPSIS
    Configure optional Azure Landing Zone security and compliance modules.

.DESCRIPTION
    Interactive script to configure which optional modules to deploy:
    - Microsoft Defender for Cloud ($1,500-$3,000/month)
    - Customer-Managed Keys / Key Vault ($250/month)
    - Azure Sentinel SIEM ($300/month)
    
    Generates a deployment-options.yaml configuration file that records
    which optional modules should be enabled during infrastructure deployment.

    ⚠ PLANNING-ONLY ARTIFACT (verified 2026-08-02): NO terraform/live/* layer
    reads .azure/deployment-options.yaml today. Running this script does NOT
    change what gets deployed — enabling defender-baseline, keyvault-cmk, or
    sentinel-siem still requires editing the corresponding Terraform
    variables/call sites by hand. The Terraform wiring is tracked in TODO.md
    ("Wire Configure-DeploymentOptions.ps1 output into Terraform"); see also
    scripts/utilities/README.md. This script has no call site anywhere in the
    pipeline and lives in scripts/utilities/ for that reason.

.EXAMPLE
    .\Configure-DeploymentOptions.ps1

    Runs interactive configuration wizard.

.EXAMPLE
    .\Configure-DeploymentOptions.ps1 -NonInteractive -EnableDefender -EnableCMK

    Non-interactive mode with specific modules enabled.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Run in non-interactive mode")]
    [switch]$NonInteractive,
    
    [Parameter(HelpMessage="Enable Microsoft Defender for Cloud")]
    [switch]$EnableDefender,
    
    [Parameter(HelpMessage="Enable Customer-Managed Keys (Key Vault CMK)")]
    [switch]$EnableCMK,
    
    [Parameter(HelpMessage="Enable Azure Sentinel SIEM")]
    [switch]$EnableSentinel,
    
    [Parameter(HelpMessage="Output file path")]
    [string]$OutputPath = "./.azure/deployment-options.yaml"
)

$ErrorActionPreference = "Stop"

# Module definitions
$MODULES = @{
    Defender = @{
        Name = "Microsoft Defender for Cloud"
        Phase = "Phase 1 (Optional)"
        Cost = "`$1,500-`$3,000/month"
        Effort = "6 hours"
        Benefits = @(
            "Vulnerability assessment for VMs"
            "Threat detection across all Azure services"
            "Security score and recommendations"
            "Just-In-Time VM access"
            "Adaptive application controls"
            "File integrity monitoring"
        )
        WhenToEnable = @(
            "Production workloads with sensitive data deployed"
            "Compliance requirements (SOC 2, ISO 27001, HIPAA)"
            "Need comprehensive threat protection"
            "Budget approved for security tooling"
        )
        Module = "terraform/modules/defender-baseline"
        Guide = "terraform/modules/defender-baseline/README.md"
    }
    CMK = @{
        Name = "Customer-Managed Keys (Key Vault Encryption)"
        Phase = "Phase 2 (Optional)"
        Cost = "`$250/month"
        Effort = "16 hours"
        Benefits = @(
            "Full control over encryption keys"
            "Audit trail for key usage"
            "Key rotation controls"
            "Compliance with encryption mandates"
            "Multi-tenant key isolation"
        )
        WhenToEnable = @(
            "Compliance mandates CMK (HIPAA, PCI-DSS, FedRAMP)"
            "Need detailed key usage audit trails"
            "Require custom key rotation policies"
            "Multi-tenant scenarios with key isolation"
        )
        Module = "terraform/modules/keyvault-cmk"
        Guide = "terraform/modules/keyvault-cmk/README.md"
    }
    Sentinel = @{
        Name = "Azure Sentinel SIEM"
        Phase = "Phase 2 (Optional)"
        Cost = "`$300/month (~5GB/day ingestion)"
        Effort = "12 hours"
        Benefits = @(
            "Centralized security event correlation"
            "ML-based threat detection"
            "Automated incident response with Logic Apps"
            "Built-in SOC workbooks and dashboards"
            "Integration with Microsoft threat intelligence"
            "SOAR capabilities (Security Orchestration)"
        )
        WhenToEnable = @(
            "Building a Security Operations Center (SOC)"
            "Compliance requires SIEM (SOC 2, ISO 27001)"
            "Need centralized security event correlation"
            "Want automated incident response workflows"
        )
        Module = "terraform/modules/sentinel-siem"
        Guide = "terraform/modules/sentinel-siem/README.md"
    }
}

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ModuleInfo {
    param([hashtable]$Module, [string]$Key)
    
    Write-Host "📦 Module: " -NoNewline
    Write-Host $Module.Name -ForegroundColor Yellow
    Write-Host "   Phase: $($Module.Phase)" -ForegroundColor Gray
    Write-Host "   Cost: $($Module.Cost)" -ForegroundColor Red
    Write-Host "   Effort: $($Module.Effort)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "✅ Benefits:" -ForegroundColor Green
    foreach ($benefit in $Module.Benefits) {
        Write-Host "   • $benefit" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "🎯 When to Enable:" -ForegroundColor Yellow
    foreach ($when in $Module.WhenToEnable) {
        Write-Host "   • $when" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "📖 Deployment Guide: $($Module.Guide)" -ForegroundColor Gray
    Write-Host ""
}

function Get-UserChoice {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    
    $choices = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    
    Write-Host "$Prompt $choices : " -NoNewline -ForegroundColor White
    $response = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes
    }
    
    return $response -match "^[Yy]"
}

function Write-Configuration {
    param([hashtable]$Config, [string]$Path)
    
    $yaml = @"
# Azure Landing Zone - Deployment Options Configuration
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
#
# This file controls which optional security and compliance modules are deployed.
# Modules are disabled by default due to additional costs and complexity.
#
# To enable a module:
#   1. Set 'enabled: true' for the desired module
#   2. Review the deployment guide in the module's README.md
#   3. Run terraform apply with the appropriate variables
#
# Cost estimates are monthly recurring costs (not including Azure resource costs).

modules:
  defender:
    name: Microsoft Defender for Cloud
    enabled: $($Config.Defender.ToString().ToLower())
    cost_per_month: 1500-3000
    phase: Phase 1 (Optional)
    module_path: terraform/modules/defender-baseline
    guide: terraform/modules/defender-baseline/README.md
    requires:
      - Log Analytics workspace (already deployed in platform-management)
      - Subscription IDs to protect
      - Security contact email
    
  cmk:
    name: Customer-Managed Keys (Key Vault Encryption)
    enabled: $($Config.CMK.ToString().ToLower())
    cost_per_month: 250
    phase: Phase 2 (Optional)
    module_path: terraform/modules/keyvault-cmk
    guide: terraform/modules/keyvault-cmk/README.md
    requires:
      - Key Vault Premium SKU
      - Managed identities for key access
      - Storage accounts to encrypt
    
  sentinel:
    name: Azure Sentinel SIEM
    enabled: $($Config.Sentinel.ToString().ToLower())
    cost_per_month: 300
    phase: Phase 2 (Optional)
    module_path: terraform/modules/sentinel-siem
    guide: terraform/modules/sentinel-siem/README.md
    requires:
      - Log Analytics workspace (already deployed in platform-management)
      - Data connectors configured
      - Analytics rules enabled

# Total monthly cost estimate (excluding Azure resource costs):
# Defender: $(if ($Config.Defender) { "`$1,500-`$3,000" } else { "`$0" })
# CMK:      $(if ($Config.CMK) { "`$250" } else { "`$0" })
# Sentinel: $(if ($Config.Sentinel) { "`$300" } else { "`$0" })
# ─────────────────────────────
# Total:    `$$($Config.TotalCost)

next_steps: |
  1. Review enabled modules and their deployment guides
  2. Ensure prerequisites are deployed (Log Analytics workspace, VNets, etc.)
  3. Follow module-specific README.md for integration steps
  4. Run terraform plan to preview changes
  5. Run terraform apply to deploy enabled modules
"@

    # Create directory if it doesn't exist
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    $yaml | Out-File -FilePath $Path -Encoding UTF8 -Force
    
    Write-Host "✅ Configuration saved to: " -NoNewline -ForegroundColor Green
    Write-Host $Path -ForegroundColor White
}

# Main script
Write-Header "Azure Landing Zone - Deployment Options Configuration"

Write-Host "This script helps you configure optional security and compliance modules." -ForegroundColor White
Write-Host "Each module has additional costs and should be enabled based on your requirements." -ForegroundColor Yellow
Write-Host ""

$config = @{
    Defender = $false
    CMK = $false
    Sentinel = $false
    TotalCost = 0
}

if ($NonInteractive) {
    Write-Host "Running in non-interactive mode..." -ForegroundColor Gray
    $config.Defender = $EnableDefender.IsPresent
    $config.CMK = $EnableCMK.IsPresent
    $config.Sentinel = $EnableSentinel.IsPresent
} else {
    # Interactive mode - ask about each module
    foreach ($key in @("Defender", "CMK", "Sentinel")) {
        $module = $MODULES[$key]
        
        Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor Gray
        Write-ModuleInfo -Module $module -Key $key
        
        $config[$key] = Get-UserChoice -Prompt "Enable $($module.Name)?" -DefaultYes $false
        
        if ($config[$key]) {
            Write-Host "   ✅ $($module.Name) will be ENABLED" -ForegroundColor Green
        } else {
            Write-Host "   ⬜ $($module.Name) will be DISABLED (default)" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

# Calculate total cost
if ($config.Defender) { $config.TotalCost += 2250 }  # Average of $1,500-$3,000
if ($config.CMK) { $config.TotalCost += 250 }
if ($config.Sentinel) { $config.TotalCost += 300 }

# Summary
Write-Header "Configuration Summary"

Write-Host "Selected Modules:" -ForegroundColor White
Write-Host "  • Microsoft Defender for Cloud:  $(if ($config.Defender) { '✅ ENABLED' } else { '⬜ Disabled' })" -ForegroundColor $(if ($config.Defender) { 'Green' } else { 'Gray' })
Write-Host "  • Customer-Managed Keys:         $(if ($config.CMK) { '✅ ENABLED' } else { '⬜ Disabled' })" -ForegroundColor $(if ($config.CMK) { 'Green' } else { 'Gray' })
Write-Host "  • Azure Sentinel SIEM:           $(if ($config.Sentinel) { '✅ ENABLED' } else { '⬜ Disabled' })" -ForegroundColor $(if ($config.Sentinel) { 'Green' } else { 'Gray' })
Write-Host ""

Write-Host "Estimated Monthly Cost: " -NoNewline -ForegroundColor Yellow
if ($config.TotalCost -eq 0) {
    Write-Host "`$0 (all modules disabled)" -ForegroundColor Green
} else {
    Write-Host "`$$($config.TotalCost)" -ForegroundColor Red
    Write-Host "(Excluding Azure resource costs)" -ForegroundColor Gray
}
Write-Host ""

# Confirm and save
if (-not $NonInteractive) {
    $confirm = Get-UserChoice -Prompt "Save this configuration?" -DefaultYes $true
    if (-not $confirm) {
        Write-Host "❌ Configuration cancelled." -ForegroundColor Red
        exit 0
    }
}

Write-Configuration -Config $config -Path $OutputPath

Write-Header "Next Steps"

if ($config.Defender -or $config.CMK -or $config.Sentinel) {
    Write-Host "🎯 You have enabled optional modules. Follow these steps:" -ForegroundColor Yellow
    Write-Host ""
    
    if ($config.Defender) {
        Write-Host "1️⃣  Microsoft Defender for Cloud:" -ForegroundColor Cyan
        Write-Host "   • Read: $($MODULES.Defender.Guide)" -ForegroundColor White
        Write-Host "   • Review prerequisites and costs" -ForegroundColor White
        Write-Host "   • Follow deployment steps in the guide" -ForegroundColor White
        Write-Host ""
    }
    
    if ($config.CMK) {
        Write-Host "2️⃣  Customer-Managed Keys:" -ForegroundColor Cyan
        Write-Host "   • Read: $($MODULES.CMK.Guide)" -ForegroundColor White
        Write-Host "   • Deploy Key Vault Premium" -ForegroundColor White
        Write-Host "   • Follow deployment steps in the guide" -ForegroundColor White
        Write-Host ""
    }
    
    if ($config.Sentinel) {
        Write-Host "3️⃣  Azure Sentinel SIEM:" -ForegroundColor Cyan
        Write-Host "   • Read: $($MODULES.Sentinel.Guide)" -ForegroundColor White
        Write-Host "   • Configure data connectors" -ForegroundColor White
        Write-Host "   • Follow deployment steps in the guide" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "4️⃣  Deploy Infrastructure:" -ForegroundColor Cyan
    Write-Host "   • Run: terraform plan" -ForegroundColor White
    Write-Host "   • Review changes carefully" -ForegroundColor White
    Write-Host "   • Run: terraform apply" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "✅ All optional modules are disabled (default configuration)." -ForegroundColor Green
    Write-Host ""
    Write-Host "You can enable modules later by:" -ForegroundColor White
    Write-Host "  1. Running this script again: .\Configure-DeploymentOptions.ps1" -ForegroundColor Gray
    Write-Host "  2. Manually editing: $OutputPath" -ForegroundColor Gray
    Write-Host "  3. Following module deployment guides in terraform/modules/" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "📖 Documentation:" -ForegroundColor White
Write-Host "   • Phase 1 tasks: docs/TODO.md" -ForegroundColor Gray
Write-Host "   • Security audit: docs/compliance/SECURITY-AUDIT-REPORT-2026-05-28.md" -ForegroundColor Gray
Write-Host "   • Deployment guide: DEPLOYMENT-GUIDE.md" -ForegroundColor Gray
Write-Host ""

Write-Host "✅ Configuration complete!" -ForegroundColor Green
