# Microsoft Defender for Cloud Baseline
# Phase 1 Remediation - Task 5.5 (Finding 5.5 - CVSS N/A - CRITICAL SECURITY CONTROL)
#
# Module contract: single subscription. Defender pricing plans are
# subscription-scoped resources with no subscription argument, so every plan
# in this module lands in the subscription the configured azurerm provider
# targets. To protect several subscriptions, instantiate this module once per
# subscription, each with a provider for that subscription. This module is
# not wired into any live stack yet.

data "azurerm_client_config" "current" {}

# Enable Microsoft Defender plans for the provider's subscription
resource "azurerm_security_center_subscription_pricing" "servers" {
  count = var.enable_defender_for_servers ? 1 : 0

  tier          = var.defender_tier
  resource_type = "VirtualMachines"
  subplan       = "P2" # Enhanced protection with vulnerability assessment
}

resource "azurerm_security_center_subscription_pricing" "app_services" {
  count = var.enable_defender_for_app_services ? 1 : 0

  tier          = var.defender_tier
  resource_type = "AppServices"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  count = var.enable_defender_for_storage ? 1 : 0

  tier          = var.defender_tier
  resource_type = "StorageAccounts"
  subplan       = "DefenderForStorageV2" # Enhanced malware scanning & sensitive data discovery
}

resource "azurerm_security_center_subscription_pricing" "sql" {
  count = var.enable_defender_for_sql ? 1 : 0

  tier          = var.defender_tier
  resource_type = "SqlServers"
}

resource "azurerm_security_center_subscription_pricing" "sql_vm" {
  count = var.enable_defender_for_sql ? 1 : 0

  tier          = var.defender_tier
  resource_type = "SqlServerVirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "containers" {
  count = var.enable_defender_for_containers ? 1 : 0

  tier          = var.defender_tier
  resource_type = "Containers"
}

resource "azurerm_security_center_subscription_pricing" "key_vault" {
  count = var.enable_defender_for_key_vault ? 1 : 0

  tier          = var.defender_tier
  resource_type = "KeyVaults"
}

resource "azurerm_security_center_subscription_pricing" "arm" {
  count = var.enable_defender_for_resource_manager ? 1 : 0

  tier          = var.defender_tier
  resource_type = "Arm"
}

resource "azurerm_security_center_subscription_pricing" "dns" {
  count = var.enable_defender_for_dns ? 1 : 0

  tier          = var.defender_tier
  resource_type = "Dns"
}

# Security contact for alert notifications
resource "azurerm_security_center_contact" "main" {
  email               = var.security_contact_email
  phone               = var.security_contact_phone
  alert_notifications = true
  alerts_to_admins    = true

  name = "default1" # Azure requirement: must be "default1"
}

# Workspace settings for Defender data collection (provider's subscription)
resource "azurerm_security_center_workspace" "main" {
  scope        = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
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
  setting_name = "MCAS" # Microsoft Cloud App Security integration
  enabled      = true
}

resource "azurerm_security_center_setting" "wdatp" {
  setting_name = "WDATP" # Windows Defender ATP integration
  enabled      = true
}
