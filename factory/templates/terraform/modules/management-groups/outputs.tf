output "root_mg_id" {
  description = "Root management group ID"
  value       = azurerm_management_group.root.id
}

output "platform_mg_id" {
  description = "Platform management group ID"
  value       = azurerm_management_group.platform.id
}

output "landingzones_mg_id" {
  description = "Landing Zones management group ID"
  value       = azurerm_management_group.landingzones.id
}

output "sandbox_mg_id" {
  description = "Sandbox management group ID"
  value       = azurerm_management_group.sandbox.id
}

output "management_group_map" {
  description = "Map of management group names to IDs"
  value = {
    root         = azurerm_management_group.root.id
    platform     = azurerm_management_group.platform.id
    landingzones = azurerm_management_group.landingzones.id
    sandbox      = azurerm_management_group.sandbox.id
  }
}
