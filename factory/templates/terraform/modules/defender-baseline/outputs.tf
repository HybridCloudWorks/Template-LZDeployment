# Microsoft Defender for Cloud Baseline Outputs

output "defender_plans_enabled" {
  description = "List of enabled Defender plans"
  value = {
    servers          = var.enable_defender_for_servers
    app_services     = var.enable_defender_for_app_services
    storage          = var.enable_defender_for_storage
    sql              = var.enable_defender_for_sql
    containers       = var.enable_defender_for_containers
    key_vault        = var.enable_defender_for_key_vault
    resource_manager = var.enable_defender_for_resource_manager
    dns              = var.enable_defender_for_dns
  }
}

output "security_contact_email" {
  description = "Security contact email for alerts"
  value       = azurerm_security_center_contact.main.email
}

output "auto_provisioning_enabled" {
  description = "Auto-provisioning status (managed by Defender platform defaults)"
  value       = "On"
}

output "protected_subscription_id" {
  description = "Subscription the Defender plans were enabled in (the provider's subscription)"
  value       = data.azurerm_client_config.current.subscription_id
}
