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

# There is deliberately no estimated_monthly_cost_usd output. The one that
# used to live here computed storage as length(nsg_ids) * retention_days *
# 0.15 — NSG-count times days times a dollar figure, which has no unit basis
# — and a flat $100 for Traffic Analytics regardless of volume. Every meter
# that actually bills here is per-GB of flow data, a quantity Terraform cannot
# know at plan time, so no honest number can be emitted from configuration
# alone. It shipped into every generated repository, where a client read it as
# a figure their own landing zone had produced. Deleted rather than repaired
# (decision 0009, open question 5). The meter structure and the per-GB formula
# are documented in README.md under "Cost".
