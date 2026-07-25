output "sandbox_resource_group_id" {
  description = "The ID of the created sandbox resource group"
  value       = try(azurerm_resource_group.sandbox[0].id, null)
}

output "sandbox_resource_group_name" {
  description = "The name of the created sandbox resource group"
  value       = try(azurerm_resource_group.sandbox[0].name, null)
}

output "sandbox_resource_group_location" {
  description = "The location of the created sandbox resource group"
  value       = try(azurerm_resource_group.sandbox[0].location, null)
}
