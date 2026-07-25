# Backup Baseline Module
# Deploys Recovery Services Vaults and Backup Vaults

# Resource group for backup services
resource "azurerm_resource_group" "backup" {
  name     = "rg-backup-${var.region_code}-${var.environment}-01"
  location = var.region
  tags     = var.tags
}

# Recovery Services Vault (for VMs, Files, SQL)
resource "azurerm_recovery_services_vault" "main" {
  name                = "rsv-platform-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.backup.name
  location            = azurerm_resource_group.backup.location
  sku                 = "Standard"
  
  storage_mode_type = var.storage_redundancy
  
  tags = var.tags
}

# Backup Vault (for Azure Backup - newer workloads)
resource "azurerm_data_protection_backup_vault" "main" {
  name                = "bv-platform-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.backup.name
  location            = azurerm_resource_group.backup.location
  datastore_type      = "VaultStore"
  redundancy          = var.backup_vault_redundancy
  
  tags = var.tags
}

# Log Analytics workspace for diagnostics
resource "azurerm_log_analytics_workspace" "backup" {
  name                = "log-backup-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.backup.name
  location            = azurerm_resource_group.backup.location
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
