output "storage_account_id" {
  description = "ID of the flow logs storage account"
  value       = azurerm_storage_account.flow_logs.id
}

output "storage_account_name" {
  description = "Name of the flow logs storage account"
  value       = azurerm_storage_account.flow_logs.name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of flow logs storage account"
  value       = azurerm_storage_account.flow_logs.primary_blob_endpoint
}

output "flow_log_ids" {
  description = "Map of NSG names to flow log resource IDs"
  value       = { for k, v in azurerm_network_watcher_flow_log.nsg_flow_logs : k => v.id }
}

output "traffic_analytics_enabled" {
  description = "Whether Traffic Analytics is enabled"
  value       = var.enable_traffic_analytics
}

output "flow_log_retention_days" {
  description = "Number of days flow logs are retained"
  value       = var.flow_log_retention_days
}

output "traffic_analytics_interval" {
  description = "Traffic Analytics processing interval (minutes)"
  value       = var.enable_traffic_analytics ? var.traffic_analytics_interval : null
}

output "private_endpoint_ip" {
  description = "Private IP address of storage account blob endpoint"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.flow_logs_blob[0].private_service_connection[0].private_ip_address : null
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD"
  value = {
    storage       = length(var.nsg_ids) * var.flow_log_retention_days * 0.15
    traffic_analytics = var.enable_traffic_analytics ? 100 : 0
    total         = length(var.nsg_ids) * var.flow_log_retention_days * 0.15 + (var.enable_traffic_analytics ? 100 : 0)
  }
}
