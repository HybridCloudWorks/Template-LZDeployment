# Outputs from Management Baseline Module

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for reference by other modules"
  value       = azurerm_log_analytics_workspace.alz.id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name"
  value       = azurerm_log_analytics_workspace.alz.name
}

output "automation_account_id" {
  description = "Automation Account ID"
  value       = azurerm_automation_account.alz.id
}

output "automation_account_name" {
  description = "Automation Account name"
  value       = azurerm_automation_account.alz.name
}

output "application_insights_id" {
  description = "Application Insights ID"
  value       = azurerm_application_insights.alz.id
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for SDK integration"
  value       = azurerm_application_insights.alz.instrumentation_key
  sensitive   = true
}

output "action_group_id" {
  description = "Alert Action Group ID"
  value       = azurerm_monitor_action_group.alz.id
}

output "resource_group_name" {
  description = "Management resource group name"
  value       = local.rg_name
}

output "management_summary" {
  description = "Summary of management resources created"
  value = {
    log_analytics_workspace = azurerm_log_analytics_workspace.alz.name
    automation_account      = azurerm_automation_account.alz.name
    application_insights    = azurerm_application_insights.alz.name
    action_group            = azurerm_monitor_action_group.alz.name
  }
}

# The Traffic Analytics block of azurerm_network_watcher_flow_log needs three
# separate facts about the workspace, and only one of them is the ARM ID above.
# workspace_id is the short GUID (the workspace "customer ID"); passing the ARM
# ID into that field type-checks, plans clean, and produces a Traffic Analytics
# configuration that never receives data. Do not collapse these three outputs.
output "log_analytics_workspace_guid" {
  description = "Log Analytics workspace GUID (short customer ID) — required by Traffic Analytics, distinct from the ARM resource ID above"
  value       = azurerm_log_analytics_workspace.alz.workspace_id
}

output "log_analytics_workspace_location" {
  description = "Region the Log Analytics workspace lives in — Traffic Analytics must be told where its workspace is, and it is also the residency declaration for processed flow metadata"
  value       = azurerm_log_analytics_workspace.alz.location
}
