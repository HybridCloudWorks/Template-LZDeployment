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
  value       = azurerm_resource_group.management.name
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
