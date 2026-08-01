output "storage_account_name" {
  description = "Name of the state storage account"
  value       = azurerm_storage_account.state.name
}

output "resource_group_name" {
  description = "Name of the state resource group"
  value       = azurerm_resource_group.state.name
}

output "container_names" {
  description = "Names of state containers"
  value       = keys(azurerm_storage_container.state_containers)
}

output "private_endpoint_enabled" {
  description = "Whether private endpoint is deployed"
  value       = var.enable_private_endpoint
}

output "private_endpoint_ip" {
  description = "Private IP address of the state storage endpoint"
  value       = var.enable_private_endpoint && var.management_subnet_id != "" ? azurerm_private_endpoint.state_blob[0].private_service_connection[0].private_ip_address : null
}

output "public_network_access" {
  description = "Public network access status (SHOULD be false for production)"
  value       = var.allow_public_access_during_setup
}

output "backend_config_hcl" {
  description = "Backend configuration for downstream Terraform modules"
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "<LAYER_SPECIFIC_CONTAINER>"
    key                  = "terraform.tfstate"
    use_azuread_auth     = true
  EOT
}
