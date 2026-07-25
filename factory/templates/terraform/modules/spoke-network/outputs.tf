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
  value       = azurerm_resource_group.spoke.name
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
