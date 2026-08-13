output "spoke_vnet_id" {
  description = "Spoke VNet ID"
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_vnet_name" {
  description = "Spoke VNet name"
  value       = azurerm_virtual_network.spoke.name
}

output "resource_group_name" {
  description = "Spoke resource group name"
  value       = local.rg_name
}

output "app_subnet_id" {
  description = "Application subnet ID"
  value       = azurerm_subnet.app.id
}

output "data_subnet_id" {
  description = "Data subnet ID"
  value       = azurerm_subnet.data.id
}

output "pe_subnet_id" {
  description = "Private endpoint subnet ID"
  value       = azurerm_subnet.pe.id
}

# Keyed by subnet role rather than by NSG name so a caller can merge several
# spokes' maps and still address one NSG. The nsg-flow-logs module uses the key
# in the flow-log resource name, so a caller merging more than one spoke must
# re-key (e.g. "dev-app") to keep those names unique per Network Watcher.
output "nsg_ids" {
  description = "Map of subnet role (app, data, pe) to NSG resource ID"
  value = {
    app  = azurerm_network_security_group.app.id
    data = azurerm_network_security_group.data.id
    pe   = azurerm_network_security_group.pe.id
  }
}
