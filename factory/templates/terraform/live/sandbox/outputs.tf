output "sandbox_resource_group_id" {
  description = "The ID of the created sandbox resource group"
  value       = module.sandbox.sandbox_resource_group_id
}

output "sandbox_resource_group_name" {
  description = "The name of the created sandbox resource group"
  value       = module.sandbox.sandbox_resource_group_name
}

output "sandbox_resource_group_location" {
  description = "The location of the created sandbox resource group"
  value       = module.sandbox.sandbox_resource_group_location
}
