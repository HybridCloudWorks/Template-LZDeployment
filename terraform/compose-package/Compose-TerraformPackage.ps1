#Requires -Version 7.0

<#
.SYNOPSIS
    Compose ALZ Terraform configuration from selected modules

.DESCRIPTION
    Generates terraform/live/{org_prefix}/ directory with main.tf, variables.tf,
    terraform.tfvars, and backend.hcl based on form selections

.PARAMETER OrgPrefix
    Organization prefix (3-8 lowercase letters)

.PARAMETER Modules
    Array of modules to deploy: hub-network, spoke-network, policy-baseline,
    backup-baseline, defender-baseline

.PARAMETER ComplianceVariant
    Compliance variant: baseline, pci-dss, hipaa, fedramp

.PARAMETER PrimaryRegion
    Primary Azure region (e.g., eastus)

.PARAMETER SecondaryRegion
    Secondary Azure region for DR (e.g., westus)

.EXAMPLE
    .\Compose-TerraformPackage.ps1 `
      -OrgPrefix "contoso" `
      -Modules @("hub-network", "spoke-network", "policy-baseline") `
      -ComplianceVariant "baseline" `
      -PrimaryRegion "eastus" `
      -SecondaryRegion "westus"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z]{3,8}$')]
    [string]$OrgPrefix,

    [Parameter(Mandatory = $true)]
    [array]$Modules,

    [Parameter(Mandatory = $false)]
    [ValidateSet('baseline', 'pci-dss', 'hipaa', 'fedramp')]
    [string]$ComplianceVariant = 'baseline',

    [Parameter(Mandatory = $false)]
    [string]$PrimaryRegion = 'eastus',

    [Parameter(Mandatory = $false)]
    [string]$SecondaryRegion = 'westus'
)

$ErrorActionPreference = 'Stop'

# ═════════════════════════════════════════════════════════════════════════════
# Initialize
# ═════════════════════════════════════════════════════════════════════════════

Write-Host "🚀 Composing ALZ Terraform configuration" -ForegroundColor Cyan
Write-Host "  Organization: $OrgPrefix" -ForegroundColor Gray
Write-Host "  Modules: $($Modules -join ', ')" -ForegroundColor Gray
Write-Host "  Compliance: $ComplianceVariant" -ForegroundColor Gray

$implementedModules = @("hub-network", "spoke-network", "policy-baseline", "backup-baseline", "defender-baseline")
$gatedModules = @("keyvault-cmk", "sentinel-siem")

$unknownModules = @($Modules | Where-Object { $_ -notin ($implementedModules + $gatedModules) })
if ($unknownModules.Count -gt 0) {
  Write-Error "Unsupported module(s): $($unknownModules -join ', '). Supported modules: $($implementedModules -join ', ')"
  exit 1
}

$blockedModules = @($Modules | Where-Object { $_ -in $gatedModules })
if ($blockedModules.Count -gt 0) {
  Write-Error "Module(s) not implemented and explicitly gated: $($blockedModules -join ', ')."
  Write-Host "Use implemented modules only: $($implementedModules -join ', ')" -ForegroundColor Yellow
  exit 1
}

# ═════════════════════════════════════════════════════════════════════════════
# Region Code Mapping (for naming conventions)
# ═════════════════════════════════════════════════════════════════════════════

$regionCodeMap = @{
    "eastus"           = "eus"
    "westus"           = "wus"
    "northeurope"      = "neu"
    "westeurope"       = "weu"
    "southcentralus"   = "scus"
    "northcentralus"   = "ncus"
    "eastus2"          = "eus2"
    "westus2"          = "wus2"
    "southeastasia"    = "sea"
    "eastasia"         = "eas"
    "australiaeast"    = "aue"
    "australiasoutheast" = "ause"
    "canadacentral"    = "cac"
    "canadaeast"       = "cae"
    "uksouth"          = "uks"
    "ukwest"           = "ukw"
    "japaneast"        = "jpe"
    "japanwest"        = "jpw"
    "koreacentral"     = "kc"
    "koreasouth"       = "ks"
    "centralindia"     = "cin"
    "southindia"       = "sin"
    "westindia"        = "win"
}

# Validate regions exist in map
if (-not $regionCodeMap.ContainsKey($PrimaryRegion)) {
    Write-Error "Primary region '$PrimaryRegion' not in region code map. Supported regions: $($regionCodeMap.Keys -join ', ')"
    exit 1
}
if (-not $regionCodeMap.ContainsKey($SecondaryRegion)) {
    Write-Error "Secondary region '$SecondaryRegion' not in region code map. Supported regions: $($regionCodeMap.Keys -join ', ')"
    exit 1
}

$primaryRegionCode = $regionCodeMap[$PrimaryRegion]
$secondaryRegionCode = $regionCodeMap[$SecondaryRegion]

Write-Host "  Primary Region Code: $PrimaryRegion → $primaryRegionCode" -ForegroundColor Gray
Write-Host "  Secondary Region Code: $SecondaryRegion → $secondaryRegionCode" -ForegroundColor Gray

# ═════════════════════════════════════════════════════════════════════════════
# Firewall Configuration Defaults (by compliance variant)
# ═════════════════════════════════════════════════════════════════════════════

$firewallConfig = @{
    "baseline"  = @{ type = "azfw"; tier = "Standard" }
    "pci-dss"   = @{ type = "azfw"; tier = "Standard" }
    "hipaa"     = @{ type = "azfw"; tier = "Premium" }
    "fedramp"   = @{ type = "azfw"; tier = "Premium" }
}

$fwConfig = $firewallConfig[$ComplianceVariant]
$firewallType = $fwConfig.type
$firewallTier = $fwConfig.tier

Write-Host "  Firewall Type: $firewallType | Tier: $firewallTier (based on $ComplianceVariant)" -ForegroundColor Gray

# ═════════════════════════════════════════════════════════════════════════════
# Directory Setup
# ═════════════════════════════════════════════════════════════════════════════

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$liveDir = Join-Path $repoRoot "terraform" "live" $OrgPrefix

# Create directory if it doesn't exist
if (-not (Test-Path $liveDir)) {
    New-Item -ItemType Directory -Force -Path $liveDir | Out-Null
    Write-Host "📁 Created directory: $liveDir" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# Generate main.tf
# ═════════════════════════════════════════════════════════════════════════════

$mainTf = @"
# Generated ALZ Terraform Configuration
# Organization: $OrgPrefix
# Compliance: $ComplianceVariant
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# DO NOT EDIT - This file is generated by Compose-TerraformPackage.ps1

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  backend "azurerm" {
    # Configuration provided via backend.hcl
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.management_subscription_id
}

# ═════════════════════════════════════════════════════════════════════════════
# Shared Resources
# ═════════════════════════════════════════════════════════════════════════════

# Central Log Analytics Workspace for diagnostics
resource "azurerm_resource_group" "central" {
  name     = "rg-${var.org_prefix}-central"
  location = var.primary_region

  tags = var.tags
}

resource "azurerm_log_analytics_workspace" "central" {
  name                = "law-${var.org_prefix}-${var.primary_region_code}"
  location            = azurerm_resource_group.central.location
  resource_group_name = azurerm_resource_group.central.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# ═════════════════════════════════════════════════════════════════════════════
# Management Groups (Always)
# ═════════════════════════════════════════════════════════════════════════════

module "management_groups" {
  source = "../../modules/management-groups"

  org_prefix                      = var.org_prefix
  identity_subscription_id        = var.identity_subscription_id
  connectivity_subscription_id    = var.connectivity_subscription_id
  management_subscription_id      = var.management_subscription_id
  workload_prod_subscription_id   = var.workload_prod_subscription_id
  workload_nonprod_subscription_id = var.workload_nonprod_subscription_id
  sandbox_subscription_id         = var.sandbox_subscription_id
}

# Management Baseline Module (Phase 2A)
module "management_baseline" {
  source = "../../modules/management-baseline"

  org_prefix        = var.org_prefix
  location          = var.primary_region
  region_code       = var.primary_region_code
  log_retention_days = 30
  tags              = var.tags

  depends_on = [module.management_groups]
}

"@

# Add hub-network if selected
if ($Modules -contains "hub-network") {
    $mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Hub Network
# ═════════════════════════════════════════════════════════════════════════════

module "hub_network" {
  source = "../../modules/hub-network"

  region                      = var.primary_region
  region_code                 = var.primary_region_code
  environment                 = var.environment
  hub_address_space           = var.hub_address_space
  firewall_type               = var.firewall_type
  azfw_tier                   = var.azfw_tier
  tags                        = var.tags
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.central.id

  depends_on = [module.management_groups]
}

"@
}

# Add spoke-network if selected
if ($Modules -contains "spoke-network") {
    $mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Spoke Networks (MVP: Single spoke for workload-prod)
# ═════════════════════════════════════════════════════════════════════════════

module "spoke_network" {
  source = "../../modules/spoke-network"

  spoke_name                = "workload-prod"
  region                    = var.primary_region
  region_code               = var.primary_region_code
  environment               = var.environment
  spoke_address_space       = "10.1.0.0/16"
  enable_hub_peering        = true
  hub_vnet_id               = module.hub_network.hub_vnet_id
  hub_vnet_name             = module.hub_network.hub_vnet_name
  hub_resource_group_name   = module.hub_network.resource_group_name
  firewall_private_ip       = module.hub_network.firewall_private_ip
  tags                      = var.tags

  depends_on = [module.hub_network]
}

# Secondary Region Hub (Phase 2C - DR Skeleton)
module "hub_network_secondary" {
  source = "../../modules/hub-network"

  region                      = var.secondary_region
  region_code                 = var.secondary_region_code
  environment                 = "dr"
  hub_address_space           = "10.100.0.0/16"
  firewall_type               = var.firewall_type
  azfw_tier                   = "Standard"
  tags                        = merge(var.tags, { Environment = "dr", Purpose = "disaster-recovery" })
  log_analytics_workspace_id  = module.management_baseline.log_analytics_workspace_id

  depends_on = [module.management_groups]
}

"@
}

# Add policy-baseline + variant
if ($Modules -contains "policy-baseline") {
    $mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Azure Policies - Compliance: $ComplianceVariant
# ═════════════════════════════════════════════════════════════════════════════

module "policy_baseline" {
  source = "../../modules/policy-baseline"

  root_mg_id              = module.management_groups.root_mg_id
  root_management_group_id = "/providers/Microsoft.Management/managementGroups/\${module.management_groups.root_mg_id}"
  platform_mg_id          = module.management_groups.platform_mg_id
  landingzones_mg_id      = module.management_groups.landingzones_mg_id
  sandbox_mg_id           = module.management_groups.sandbox_mg_id
  location                = var.primary_region
  allowed_locations       = var.allowed_locations
  compliance_variant      = var.compliance_variant

  depends_on = [module.management_groups]
}

"@
}

# Add backup-baseline if selected
if ($Modules -contains "backup-baseline") {
    $mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Backup Baseline
# ═════════════════════════════════════════════════════════════════════════════

module "backup_baseline" {
  source = "../../modules/backup-baseline"

  resource_group_name = "rg-${OrgPrefix}-backup"
  location            = var.primary_region
  org_prefix          = var.org_prefix

  depends_on = [module.management_groups]
}

"@
}

# Add defender-baseline if selected
if ($Modules -contains "defender-baseline") {
    $mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Microsoft Defender Baseline
# ═════════════════════════════════════════════════════════════════════════════

module "defender_baseline" {
  source = "../../modules/defender-baseline"

  resource_group_name = "rg-${OrgPrefix}-security"
  location            = var.primary_region
  org_prefix          = var.org_prefix

  depends_on = [module.management_groups]
}

"@
}

# Add outputs section
$mainTf += @"
# ═════════════════════════════════════════════════════════════════════════════
# Outputs
# ═════════════════════════════════════════════════════════════════════════════

output "deployment_summary" {
  description = "Summary of deployed ALZ configuration"
  value = {
    org_prefix         = var.org_prefix
    primary_region     = var.primary_region
    secondary_region   = var.secondary_region
    compliance_variant = var.compliance_variant
    firewall_tier      = var.azfw_tier
    deployed_modules   = [$(($Modules | ForEach-Object { "`"$_`"" }) -join ', ')]
  }
}

output "management_groups" {
  description = "Management group hierarchy"
  value       = module.management_groups.management_group_map
  sensitive   = false
}

$(if ($Modules -contains "hub-network") { @"
output "hub_network" {
  description = "Hub network configuration"
  value = {
    vnet_id             = module.hub_network.hub_vnet_id
    vnet_name           = module.hub_network.hub_vnet_name
    resource_group_name = module.hub_network.resource_group_name
    firewall_private_ip = module.hub_network.firewall_private_ip
    firewall_type       = module.hub_network.firewall_type
  }
}
"@ } else { "# Hub network not deployed" })

$(if ($Modules -contains "spoke-network") { @"
output "spoke_networks" {
  description = "Spoke network configuration"
  value = {
    spoke_name       = "workload-prod"
    spoke_vnet_id    = module.spoke_network.spoke_vnet_id
    peering_status   = "peered-to-hub"
  }
}
"@ } else { "# Spoke networks not deployed" })
"@

Set-Content -Path (Join-Path $liveDir "main.tf") -Value $mainTf
Write-Host "✅ Generated main.tf" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# Generate variables.tf
# ═════════════════════════════════════════════════════════════════════════════

$variablesTf = @"
# Variables for $OrgPrefix landing zone
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

variable "org_prefix" {
  description = "Organization prefix"
  type        = string
  default     = "$OrgPrefix"
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
  default     = "$PrimaryRegion"
}

variable "primary_region_code" {
  description = "Primary region code for naming"
  type        = string
  default     = "$primaryRegionCode"
}

variable "secondary_region" {
  description = "Secondary Azure region (for DR skeleton)"
  type        = string
  default     = "$SecondaryRegion"
}

variable "secondary_region_code" {
  description = "Secondary region code for naming"
  type        = string
  default     = "$secondaryRegionCode"
}

variable "management_subscription_id" {
  description = "Subscription ID for management resources"
  type        = string
}

variable "identity_subscription_id" {
  description = "Subscription ID for identity resources"
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Subscription ID for connectivity resources"
  type        = string
}

variable "workload_prod_subscription_id" {
  description = "Subscription ID for production workloads"
  type        = string
}

variable "workload_nonprod_subscription_id" {
  description = "Subscription ID for non-production workloads"
  type        = string
}

variable "sandbox_subscription_id" {
  description = "Subscription ID for sandbox"
  type        = string
}

variable "hub_address_space" {
  description = "Hub VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "firewall_type" {
  description = "Firewall type: azfw (Azure Firewall), palo, or fortinet"
  type        = string
  default     = "$firewallType"
}

variable "azfw_tier" {
  description = "Azure Firewall tier: Standard or Premium"
  type        = string
  default     = "$firewallTier"
}

variable "allowed_locations" {
  description = "Allowed Azure regions for policy enforcement"
  type        = list(string)
  default     = ["$PrimaryRegion", "$SecondaryRegion"]
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "compliance_variant" {
  description = "Compliance variant: baseline, pci-dss, hipaa, or fedramp"
  type        = string
  default     = "$ComplianceVariant"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Organization = "$OrgPrefix"
    Environment  = "production"
    Compliance   = "$ComplianceVariant"
    CreatedBy    = "terraform"
    ManagedBy    = "terraform"
  }
}
"@

Set-Content -Path (Join-Path $liveDir "variables.tf") -Value $variablesTf
Write-Host "✅ Generated variables.tf" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# Generate terraform.tfvars
# ═════════════════════════════════════════════════════════════════════════════

$terraformTfvars = @"
# Terraform variables for $OrgPrefix landing zone
# ⚠️  EDIT THIS FILE with your Azure subscription IDs and Terraform Cloud settings

org_prefix             = "$OrgPrefix"
primary_region         = "$PrimaryRegion"
primary_region_code    = "$primaryRegionCode"
secondary_region       = "$SecondaryRegion"
secondary_region_code  = "$secondaryRegionCode"
environment            = "production"
compliance_variant     = "$ComplianceVariant"

# Firewall Configuration (set based on compliance variant)
firewall_type = "$firewallType"
azfw_tier     = "$firewallTier"

# ⚠️  TODO: Update these with your actual subscription IDs
management_subscription_id      = "00000000-0000-0000-0000-000000000000"
identity_subscription_id        = "00000000-0000-0000-0000-000000000000"
connectivity_subscription_id    = "00000000-0000-0000-0000-000000000000"
workload_prod_subscription_id   = "00000000-0000-0000-0000-000000000000"
workload_nonprod_subscription_id = "00000000-0000-0000-0000-000000000000"
sandbox_subscription_id         = "00000000-0000-0000-0000-000000000000"

# Network Configuration
hub_address_space = "10.0.0.0/16"

# Allowed Azure regions (for policy enforcement)
allowed_locations = ["$PrimaryRegion", "$SecondaryRegion"]

# Common tags
tags = {
  Organization = "$OrgPrefix"
  Environment  = "production"
  Compliance   = "$ComplianceVariant"
  CostCenter   = "engineering"
  Owner        = "platform-team"
  ManagedBy    = "terraform"
}
"@

Set-Content -Path (Join-Path $liveDir "terraform.tfvars") -Value $terraformTfvars
Write-Host "✅ Generated terraform.tfvars (UPDATE WITH YOUR SUBSCRIPTION IDS)" -ForegroundColor Yellow

# ═════════════════════════════════════════════════════════════════════════════
# Generate backend.hcl
# ═════════════════════════════════════════════════════════════════════════════

$backendHcl = @"
# Terraform Cloud backend configuration
# Fill in with your Terraform Cloud details

workspaces {
  name = "${OrgPrefix}-landing-zone"
}

hostname     = "app.terraform.io"
organization = "YOUR-ORG-HERE"  # TODO: Update with your TFC organization
"@

Set-Content -Path (Join-Path $liveDir "backend.hcl") -Value $backendHcl
Write-Host "✅ Generated backend.hcl (UPDATE WITH YOUR TFC DETAILS)" -ForegroundColor Yellow

# ═════════════════════════════════════════════════════════════════════════════
# Generate deployment manifest
# ═════════════════════════════════════════════════════════════════════════════

$manifest = @"
apiVersion: alz/v1
kind: DeploymentManifest
metadata:
  name: $OrgPrefix
  timestamp: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
spec:
  orgPrefix: $OrgPrefix
  compliance: $ComplianceVariant
  regions:
    primary: $PrimaryRegion
    secondary: $SecondaryRegion
  modules:
$(($Modules | ForEach-Object { "    - $_" }) -join "`n")
  terraformDir: terraform/live/$OrgPrefix
  estimatedMonthlyCost: TODO
"@

Set-Content -Path (Join-Path $liveDir "deployment-manifest.yaml") -Value $manifest
Write-Host "✅ Generated deployment-manifest.yaml" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ Terraform configuration composed successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📂 Location: $liveDir" -ForegroundColor White
Write-Host "📋 Files generated:" -ForegroundColor White
Write-Host "   ✓ main.tf" -ForegroundColor Green
Write-Host "   ✓ variables.tf" -ForegroundColor Green
Write-Host "   ✓ terraform.tfvars (⚠️  EDIT WITH YOUR SUBSCRIPTION IDS)" -ForegroundColor Yellow
Write-Host "   ✓ backend.hcl (⚠️  EDIT WITH YOUR TFC DETAILS)" -ForegroundColor Yellow
Write-Host "   ✓ deployment-manifest.yaml" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 Next steps:" -ForegroundColor White
Write-Host "   1. Edit terraform.tfvars with your subscription IDs" -ForegroundColor White
Write-Host "   2. Edit backend.hcl with your Terraform Cloud organization" -ForegroundColor White
Write-Host "   3. Run: terraform init -backend-config=backend.hcl" -ForegroundColor White
Write-Host "   4. Run: terraform plan" -ForegroundColor White
Write-Host "   5. Run: terraform apply" -ForegroundColor White
Write-Host ""
