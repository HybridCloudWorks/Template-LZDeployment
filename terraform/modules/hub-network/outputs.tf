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
  description = "Firewall private IP for routing; null when firewall_type is \"none\""
  value       = local.firewall_private_ip
}

output "route_table_id" {
  description = "Route table ID for spoke associations; null when firewall_type is \"none\""
  value       = one(azurerm_route_table.to_firewall[*].id)
}

output "gateway_subnet_id" {
  description = "Gateway subnet ID"
  value       = azurerm_subnet.gateway.id
}

output "firewall_type" {
  description = "Deployed firewall type"
  value       = var.firewall_type
}

output "firewall_policy_id" {
  description = "ID of the Azure Firewall Policy"
  value       = var.firewall_type == "azfw" && var.enable_firewall_threat_intel ? azurerm_firewall_policy.hub[0].id : null
}

output "firewall_threat_intel_mode" {
  description = "Threat Intelligence mode configured"
  value       = var.enable_firewall_threat_intel ? var.firewall_threat_intel_mode : "Disabled"
}

output "firewall_idps_mode" {
  description = "IDPS mode configured (Premium SKU only)"
  value       = var.azfw_tier == "Premium" && var.enable_firewall_threat_intel ? var.firewall_idps_mode : "Not Available"
}

output "firewall_diagnostics_enabled" {
  description = "Whether threat intelligence diagnostics are enabled"
  value       = var.enable_firewall_threat_intel
}
