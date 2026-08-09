output "log_analytics_workspace_id" {
  description = "Central Log Analytics workspace resource ID (consumed by the connectivity layer for hub diagnostics)"
  value       = module.management_baseline.log_analytics_workspace_id
}

# Traffic Analytics needs the short GUID and the workspace region as well as
# the ARM ID above; the connectivity layer re-exports all three so the workload
# layers can reach them through the connectivity read they already perform.
output "log_analytics_workspace_guid" {
  description = "Central Log Analytics workspace GUID (short customer ID), required by NSG flow-log Traffic Analytics"
  value       = module.management_baseline.log_analytics_workspace_guid
}

output "log_analytics_workspace_location" {
  description = "Region of the central Log Analytics workspace, required by NSG flow-log Traffic Analytics"
  value       = module.management_baseline.log_analytics_workspace_location
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
