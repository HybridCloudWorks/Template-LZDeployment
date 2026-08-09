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

# Same shape as spoke-network's nsg_ids so a caller passes one value straight
# into nsg-flow-logs. Keyed by NSG role rather than by resource name, and the
# nsg-flow-logs module uses the key in the flow-log resource name, so a caller
# merging both hubs' maps must re-key to keep those names unique per Network
# Watcher. The hub creates fw_mgmt only for an NVA firewall (local.has_nva),
# so this is an EMPTY MAP — not null, and never an index into a zero-length
# resource — for an azfw hub; nsg-flow-logs' for_each then enables nothing.
output "nsg_ids" {
  description = "Map of hub NSG role (fw_mgmt) to NSG resource ID. Empty when the hub deploys no NVA firewall."
  value = local.has_nva ? {
    fw_mgmt = azurerm_network_security_group.fw_mgmt[0].id
  } : {}
}
