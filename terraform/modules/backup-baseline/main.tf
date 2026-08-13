# Backup Baseline Module
# Deploys Recovery Services Vaults and Backup Vaults

# Resource group for backup services
resource "azurerm_resource_group" "backup" {
  count    = var.student_resource_group_name == "" ? 1 : 0
  name     = "rg-backup-${var.region_code}-${var.environment}-01"
  location = var.region
  tags     = var.tags
}

# DEMO WIRING (TechCon workshop) — remove after the event.
# Reads the student's pre-existing group instead of creating one. Students hold
# Reader and cannot create resource groups; the shared deploying identity could,
# but 30 students creating identically-named groups in one subscription would
# collide on the second apply.
data "azurerm_resource_group" "student" {
  count = var.student_resource_group_name == "" ? 0 : 1
  name  = var.student_resource_group_name
}

locals {
  rg_name     = var.student_resource_group_name == "" ? azurerm_resource_group.backup[0].name : data.azurerm_resource_group.student[0].name
  rg_location = var.student_resource_group_name == "" ? azurerm_resource_group.backup[0].location : data.azurerm_resource_group.student[0].location
}

# Recovery Services Vault (for VMs, Files, SQL)
resource "azurerm_recovery_services_vault" "main" {
  # CKV2_AZURE_35. A vault needs an identity to reach a CMK-encrypted or
  # private-endpoint-fronted storage target; SystemAssigned costs nothing and
  # is the identity every later hardening step will want (TODO item 2.15).
  identity {
    type = "SystemAssigned"
  }

  name                = "rsv-platform-${var.region_code}-${var.environment}-01"
  resource_group_name = local.rg_name
  location            = local.rg_location
  sku                 = "Standard"

  storage_mode_type = var.storage_redundancy

  tags = var.tags
}

# Backup Vault (for Azure Backup - newer workloads)
resource "azurerm_data_protection_backup_vault" "main" {
  name                = "bv-platform-${var.region_code}-${var.environment}-01"
  resource_group_name = local.rg_name
  location            = local.rg_location
  datastore_type      = "VaultStore"
  redundancy          = var.backup_vault_redundancy

  tags = var.tags
}

# Log Analytics workspace for diagnostics
resource "azurerm_log_analytics_workspace" "backup" {
  name                = "log-backup-${var.region_code}-${var.environment}-01"
  resource_group_name = local.rg_name
  location            = local.rg_location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Diagnostic settings for RSV
resource "azurerm_monitor_diagnostic_setting" "rsv" {
  name                       = "diag-rsv"
  target_resource_id         = azurerm_recovery_services_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.backup.id

  enabled_log {
    category = "AzureBackupReport"
  }

  enabled_log {
    category = "CoreAzureBackup"
  }

  enabled_log {
    category = "AddonAzureBackupJobs"
  }

  enabled_log {
    category = "AddonAzureBackupAlerts"
  }

  enabled_log {
    category = "AddonAzureBackupPolicy"
  }

  enabled_log {
    category = "AddonAzureBackupStorage"
  }

  enabled_metric {
    category = "Health"
  }
}
