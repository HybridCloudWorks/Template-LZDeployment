# Platform Management - Backup Vaults
# Deploy after connectivity layer

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.management_subscription_id
}

locals {
  common_tags = merge(var.default_tags, {
    layer = "platform-management"
  })
}

# Primary region backup baseline
module "backup_primary" {
  source = "../../modules/backup-baseline"

  region                  = var.primary_region
  region_code             = var.primary_region_code
  environment             = "prod"
  storage_redundancy      = "GeoRedundant"
  backup_vault_redundancy = "GeoRedundant"
  tags                    = local.common_tags
}

# DR region backup baseline
module "backup_dr" {
  source = "../../modules/backup-baseline"

  region                  = var.dr_region
  region_code             = var.dr_region_code
  environment             = "prod"
  storage_redundancy      = "GeoRedundant"
  backup_vault_redundancy = "GeoRedundant"
  tags                    = local.common_tags
}

# Azure Automation Account for sandbox cleanup
resource "azurerm_resource_group" "automation" {
  name     = "rg-automation-${var.primary_region_code}-prod-01"
  location = var.primary_region
  tags     = local.common_tags
}

resource "azurerm_automation_account" "main" {
  name                = "aa-platform-${var.primary_region_code}-prod-01"
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location
  sku_name            = "Basic"
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

# Runbook for sandbox cleanup (PowerShell)
resource "azurerm_automation_runbook" "sandbox_cleanup" {
  name                    = "Cleanup-ExpiredSandboxResources"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  location                = azurerm_resource_group.automation.location
  runbook_type            = "PowerShell"
  log_verbose             = true
  log_progress            = true
  description             = "Deletes sandbox resources with expiry_date older than 30 days"

  content = file("${path.module}/../../scripts/Cleanup-ExpiredSandboxResources.ps1")

  tags = local.common_tags
}

# Schedule sandbox cleanup daily at 02:00 UTC
resource "azurerm_automation_schedule" "sandbox_cleanup_daily" {
  name                    = "Daily-Sandbox-Cleanup"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  start_time              = "2026-06-01T02:00:00Z"
  description             = "Daily sandbox cleanup at 02:00 UTC"
}

resource "azurerm_automation_job_schedule" "sandbox_cleanup" {
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  runbook_name            = azurerm_automation_runbook.sandbox_cleanup.name
  schedule_name           = azurerm_automation_schedule.sandbox_cleanup_daily.name

  parameters = {
    sandbox_subscription_id = var.sandbox_subscription_id
    dry_run                 = "false"
  }
}
