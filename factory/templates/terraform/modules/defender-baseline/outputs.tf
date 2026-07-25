# Microsoft Defender for Cloud Baseline Outputs

output "defender_plans_enabled" {
  description = "List of enabled Defender plans"
  value = {
    servers         = var.enable_defender_for_servers
    app_services    = var.enable_defender_for_app_services
    storage         = var.enable_defender_for_storage
    sql             = var.enable_defender_for_sql
    containers      = var.enable_defender_for_containers
    key_vault       = var.enable_defender_for_key_vault
    resource_manager = var.enable_defender_for_resource_manager
    dns             = var.enable_defender_for_dns
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

output "subscriptions_protected" {
  description = "Number of subscriptions with Defender enabled"
  value       = length(var.subscriptions)
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for enabled Defender plans (USD)"
  value = sum([
    var.enable_defender_for_servers ? 15 * length(var.subscriptions) : 0,  # $15/server/month (estimated)
    var.enable_defender_for_app_services ? 15 * length(var.subscriptions) : 0,  # $15/app/month
    var.enable_defender_for_storage ? 10 * length(var.subscriptions) : 0,  # $10/storage account/month
    var.enable_defender_for_sql ? 15 * length(var.subscriptions) : 0,  # $15/SQL server/month
    var.enable_defender_for_containers ? 7 * length(var.subscriptions) : 0,  # $7/vCore/month for AKS
    var.enable_defender_for_key_vault ? 0.02 * length(var.subscriptions) : 0,  # $0.02/10k operations
    var.enable_defender_for_resource_manager ? 0.10 * length(var.subscriptions) : 0,  # $0.10/10k operations
    var.enable_defender_for_dns ? 0.70 * length(var.subscriptions) : 0,  # $0.70/million queries
  ])
}

output "next_steps" {
  description = "Post-deployment actions"
  value = <<-EOT
    ✅ Microsoft Defender for Cloud enabled successfully!
    
    Next Steps:
    1. Review Security Score: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/0
    2. Configure alert rules: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/17
    3. Review recommendations: https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/5
    4. Set up workflow automation (optional): https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/18
    5. Enable Just-In-Time VM access (optional): https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/19
    
    Security Contact:
    - Email: ${azurerm_security_center_contact.main.email}
    - Alerts: Enabled
    - Admin notifications: Enabled
    
    Enabled Plans:
    ${var.enable_defender_for_servers ? "✅ Servers (VMs)" : "⬜ Servers"}
    ${var.enable_defender_for_app_services ? "✅ App Services" : "⬜ App Services"}
    ${var.enable_defender_for_storage ? "✅ Storage Accounts" : "⬜ Storage"}
    ${var.enable_defender_for_sql ? "✅ SQL Databases" : "⬜ SQL"}
    ${var.enable_defender_for_containers ? "✅ Containers (AKS)" : "⬜ Containers"}
    ${var.enable_defender_for_key_vault ? "✅ Key Vaults" : "⬜ Key Vault"}
    ${var.enable_defender_for_resource_manager ? "✅ Azure Resource Manager" : "⬜ ARM"}
    ${var.enable_defender_for_dns ? "✅ DNS" : "⬜ DNS"}
    
    Estimated Monthly Cost: ~$${sum([
      var.enable_defender_for_servers ? 15 * length(var.subscriptions) : 0,
      var.enable_defender_for_app_services ? 15 * length(var.subscriptions) : 0,
      var.enable_defender_for_storage ? 10 * length(var.subscriptions) : 0,
      var.enable_defender_for_sql ? 15 * length(var.subscriptions) : 0,
      var.enable_defender_for_containers ? 7 * length(var.subscriptions) : 0,
      var.enable_defender_for_key_vault ? 0.02 * length(var.subscriptions) : 0,
      var.enable_defender_for_resource_manager ? 0.10 * length(var.subscriptions) : 0,
      var.enable_defender_for_dns ? 0.70 * length(var.subscriptions) : 0,
    ])} (varies by resource count)
  EOT
}
