output "recovery_services_vault_id" {
  description = "Recovery Services Vault ID"
  value       = azurerm_recovery_services_vault.main.id
}

output "backup_vault_id" {
  description = "Backup Vault ID"
  value       = azurerm_data_protection_backup_vault.main.id
}

output "resource_group_name" {
  description = "Backup resource group name"
  value       = azurerm_resource_group.backup.name
}
