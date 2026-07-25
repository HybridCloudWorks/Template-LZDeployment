output "hub_vnet_id" {
  description = "Hub VNet ID"
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Hub VNet name"
  value       = azurerm_virtual_network.hub.name
}

output "resource_group_name" {
  description = "Hub resource group name"
  value       = azurerm_resource_group.hub.name
}

output "firewall_private_ip" {
  description = "Firewall private IP for routing"
  value       = local.firewall_private_ip
}

output "route_table_id" {
  description = "Route table ID for spoke associations"
  value       = azurerm_route_table.to_firewall.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.hub.id
}

output "gateway_subnet_id" {
  description = "Gateway subnet ID"
  value       = azurerm_subnet.gateway.id
}

output "firewall_type" {
  description = "Deployed firewall type"
  value       = var.firewall_type
}
