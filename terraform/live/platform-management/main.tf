# Platform Management - Backup Vaults
# Deploy after connectivity layer

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # Stated 5.0 default (decision 0006): the provider registers no resource
  # providers — the broker registers the required namespaces at bootstrap.
  subscription_id                 = var.management_subscription_id
  resource_provider_registrations = "none"
}

locals {
  common_tags = merge(var.default_tags, {
    layer = "platform-management"
  })
}

# Management baseline - central Log Analytics workspace, automation account,
# Application Insights, and alerting for the platform
module "management_baseline" {
  source = "../../modules/management-baseline"

  org_prefix            = var.org_prefix
  location              = var.primary_region
  region_code           = var.primary_region_code
  log_retention_days    = var.log_retention_days
  alert_email_receivers = var.alert_email_receivers
  tags                  = local.common_tags
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

# Schedule sandbox cleanup daily
resource "azurerm_automation_schedule" "sandbox_cleanup_daily" {
  name                    = "Daily-Sandbox-Cleanup"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Day"
  interval                = 1
  timezone                = "UTC"
  description             = "Daily sandbox cleanup"

  # Azure rejects a start_time in the past, so a literal date expires the
  # moment it is written. Derived at plan time and then ignored, because
  # otherwise every subsequent plan shows a diff on a value that only
  # matters once.
  start_time = timeadd(plantimestamp(), "24h")

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "sandbox_cleanup" {
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  runbook_name            = azurerm_automation_runbook.sandbox_cleanup.name
  schedule_name           = azurerm_automation_schedule.sandbox_cleanup_daily.name

  # Keys must match the runbook's param() block exactly. DryRun defaults to
  # "true": flipping it to "false" (real deletions) is a deliberate operator
  # decision, not a default.
  parameters = {
    SandboxSubscriptionId = var.sandbox_subscription_id
    DryRun                = "true"
  }
}

# The runbook enumerates and deletes expired sandbox resource groups, so the
# automation account's system-assigned identity needs rights in the sandbox
# subscription; without this assignment every run fails at login.
# principal_type must be set explicitly: the ABAC delegation condition on the
# granting identity evaluates PrincipalType from the create request, and the
# provider omits it unless this argument is set — the grant would be denied.
# skip_service_principal_aad_check is deliberately off; if the same-apply MSI
# hits AAD replication lag, retry the apply rather than skip the check.
resource "azurerm_role_assignment" "sandbox_cleanup" {
  scope                = "/subscriptions/${var.sandbox_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
