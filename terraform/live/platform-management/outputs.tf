output "log_analytics_workspace_id" {
  description = "Central Log Analytics workspace resource ID (consumed by the connectivity layer for hub diagnostics)"
  value       = module.management_baseline.log_analytics_workspace_id
}

output "backup_primary_rsv_id" {
  value = module.backup_primary.recovery_services_vault_id
}

output "backup_dr_rsv_id" {
  value = module.backup_dr.recovery_services_vault_id
}

output "automation_account_id" {
  value = azurerm_automation_account.main.id
}

output "automation_identity_principal_id" {
  value = azurerm_automation_account.main.identity[0].principal_id
}
