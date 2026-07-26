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
  EOT
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value       = <<-EOT
    ✅ Bootstrap complete! State storage is ${var.allow_public_access_during_setup ? "⚠️  PUBLICLY ACCESSIBLE" : "🔒 SECURED"}
    
    Security Status:
    - Public network access: ${var.allow_public_access_during_setup ? "ENABLED (INSECURE)" : "DISABLED (SECURE)"}
    - Private endpoint: ${var.enable_private_endpoint ? "DEPLOYED" : "NOT DEPLOYED"}
    - TLS 1.2 minimum: ENFORCED ✅
    - Blob versioning: ENABLED ✅
    - Soft delete: 30 days ✅
    
    ${var.allow_public_access_during_setup ? "⚠️  WARNING: Public access enabled. Complete Task 1.2 remediation:" : ""}
    ${var.allow_public_access_during_setup ? "   1. Deploy management VNet first" : ""}
    ${var.allow_public_access_during_setup ? "   2. Re-run with private endpoint variables" : ""}
    ${var.allow_public_access_during_setup ? "   3. Set allow_public_access_during_setup = false" : ""}
    
    Next Deployment Steps:
    1. Copy backend config to your backend.hcl files:
       ${self.backend_config_hcl}
    
    2. Configure GitHub OIDC with storage account access
    
    3. Deploy layers in order:
       - Global: cd ../live/global && terraform init -backend-config=backend.hcl
       - Connectivity: cd ../live/platform-connectivity
       - Management: cd ../live/platform-management
  EOT
}
