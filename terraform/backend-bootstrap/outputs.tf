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

output "layer_state_containers" {
  # Consumed by scripts/New-BackendConfig.ps1 to emit each live layer's
  # backend.hcl. Keys are the terraform/live/<layer> directory names; values
  # must be containers the state_containers resource actually creates.
  description = "Map of live layer name to the state container that layer's backend.hcl uses"
  value = {
    "global"                = azurerm_storage_container.state_containers["global-mgmt-groups"].name
    "platform-connectivity" = azurerm_storage_container.state_containers["platform-connectivity"].name
    "platform-management"   = azurerm_storage_container.state_containers["platform-management"].name
    "workloads-prod"        = azurerm_storage_container.state_containers["workloads-prod"].name
  }
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
