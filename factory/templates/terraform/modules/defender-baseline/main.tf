# Microsoft Defender for Cloud Baseline
# Phase 1 Remediation - Task 5.5 (Finding 5.5 - CVSS N/A - CRITICAL SECURITY CONTROL)
# Enables comprehensive threat protection across all Azure subscriptions

# Enable Microsoft Defender for Subscriptions
resource "azurerm_security_center_subscription_pricing" "servers" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_servers }
  
  tier          = each.value.tier
  resource_type = "VirtualMachines"
  subplan       = "P2"  # Enhanced protection with vulnerability assessment
}

resource "azurerm_security_center_subscription_pricing" "app_services" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_app_services }
  
  tier          = each.value.tier
  resource_type = "AppServices"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_storage }
  
  tier          = each.value.tier
  resource_type = "StorageAccounts"
  subplan       = "DefenderForStorageV2"  # Enhanced malware scanning & sensitive data discovery
}

resource "azurerm_security_center_subscription_pricing" "sql" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_sql }
  
  tier          = each.value.tier
  resource_type = "SqlServers"
}

resource "azurerm_security_center_subscription_pricing" "sql_vm" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_sql }
  
  tier          = each.value.tier
  resource_type = "SqlServerVirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "containers" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_containers }
  
  tier          = each.value.tier
  resource_type = "Containers"
}

resource "azurerm_security_center_subscription_pricing" "key_vault" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_key_vault }
  
  tier          = each.value.tier
  resource_type = "KeyVaults"
}

resource "azurerm_security_center_subscription_pricing" "arm" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_resource_manager }
  
  tier          = each.value.tier
  resource_type = "Arm"
}

resource "azurerm_security_center_subscription_pricing" "dns" {
  for_each = { for k, v in var.subscriptions : k => v if var.enable_defender_for_dns }
  
  tier          = each.value.tier
  resource_type = "Dns"
}

# Security contact for alert notifications
resource "azurerm_security_center_contact" "main" {
  email               = var.security_contact_email
  phone               = var.security_contact_phone
  alert_notifications = true
  alerts_to_admins    = true
  
  name = "default1"  # Azure requirement: must be "default1"
}

# Workspace settings for Defender data collection
resource "azurerm_security_center_workspace" "main" {
  scope        = "/subscriptions/${values(var.subscriptions)[0].id}"  # Apply to first subscription as example
  workspace_id = var.log_analytics_workspace_id
}

# Built-in security policies (enabled by default with Defender)
# These policies are automatically applied when Defender plans are enabled:
# - VM vulnerability assessment
# - Storage account secure transfer
# - SQL encryption at rest
# - Container image scanning
# - Network security groups on subnets

# Enable continuous export of Defender data to Log Analytics
resource "azurerm_security_center_setting" "mcas" {
  setting_name = "MCAS"  # Microsoft Cloud App Security integration
  enabled      = true
}

resource "azurerm_security_center_setting" "wdatp" {
  setting_name = "WDATP"  # Windows Defender ATP integration
  enabled      = true
}