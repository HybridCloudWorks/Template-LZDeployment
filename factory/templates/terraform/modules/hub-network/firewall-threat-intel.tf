# Azure Firewall Policy with Threat Intelligence
# Task 5.3: Configure Azure Firewall Threat Intelligence (Phase 2)

resource "azurerm_firewall_policy" "hub" {
  count               = var.firewall_type == "azfw" && var.enable_firewall_threat_intel ? 1 : 0
  name                = "azfwpol-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = var.azfw_tier

  # Threat Intelligence
  threat_intelligence_mode = var.firewall_threat_intel_mode

  threat_intelligence_allowlist {
    # Example allowlist - customize based on your needs
    # ip_addresses = ["1.2.3.4"]  # Trusted IPs that should bypass threat intel
    # fqdns        = ["example.com"]  # Trusted FQDNs that should bypass threat intel
    ip_addresses = var.firewall_threat_intel_allowlist_ips
    fqdns        = var.firewall_threat_intel_allowlist_fqdns
  }

  # DNS Configuration
  dns {
    proxy_enabled = true
    servers       = var.firewall_dns_servers
  }

  # Intrusion Detection and Prevention System (IDPS) - Premium SKU only
  dynamic "intrusion_detection" {
    for_each = var.azfw_tier == "Premium" ? [1] : []
    content {
      mode = var.firewall_idps_mode

      # Signature overrides - customize based on your environment
      # signature_overrides {
      #   id    = "2024897"  # Example signature ID
      #   state = "Alert"    # Alert, Deny, or Off
      # }

      dynamic "signature_overrides" {
        for_each = var.firewall_idps_signature_overrides
        content {
          id    = signature_overrides.value.id
          state = signature_overrides.value.state
        }
      }

      dynamic "traffic_bypass" {
        for_each = var.firewall_idps_traffic_bypass
        content {
          name                  = traffic_bypass.value.name
          protocol              = traffic_bypass.value.protocol
          description           = traffic_bypass.value.description
          destination_addresses = traffic_bypass.value.destination_addresses
          destination_ports     = traffic_bypass.value.destination_ports
          source_addresses      = traffic_bypass.value.source_addresses
          source_ip_groups      = traffic_bypass.value.source_ip_groups
        }
      }
    }
  }

  # TLS Inspection - Premium SKU only
  dynamic "tls_certificate" {
    for_each = var.azfw_tier == "Premium" && var.firewall_enable_tls_inspection ? [1] : []
    content {
      key_vault_secret_id = var.firewall_tls_certificate_key_vault_secret_id
      name                = "tls-inspection-cert"
    }
  }

  tags = merge(
    var.tags,
    {
      component = "security"
      purpose   = "threat-intelligence"
    }
  )
}

# Link Firewall Policy to Firewall
resource "azurerm_firewall" "hub_with_policy" {
  count               = var.firewall_type == "azfw" && var.enable_firewall_threat_intel ? 1 : 0
  name                = "azfw-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.azfw_tier
  zones               = var.availability_zones
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.azfw[0].id
    public_ip_address_id = azurerm_public_ip.azfw[0].id
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Diagnostic Settings for Firewall Policy
resource "azurerm_monitor_diagnostic_setting" "firewall_policy" {
  count                      = var.firewall_type == "azfw" && var.enable_firewall_threat_intel ? 1 : 0
  name                       = "diag-azfwpol-${var.region_code}-${var.environment}"
  target_resource_id         = azurerm_firewall_policy.hub[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Firewall Policy logs - currently limited logs for policy itself
  # Most logs come from the firewall resource

  enabled_metric {
    category = "AllMetrics"
  }
}

# Diagnostic Settings for Firewall (Threat Intelligence Logs)
resource "azurerm_monitor_diagnostic_setting" "firewall_threat_intel" {
  count                      = var.firewall_type == "azfw" && var.enable_firewall_threat_intel ? 1 : 0
  name                       = "diag-azfw-threatintel-${var.region_code}-${var.environment}"
  target_resource_id         = azurerm_firewall.hub_with_policy[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_log {
    category = "AzureFirewallDnsProxy"
  }

  # Threat Intelligence logs
  enabled_log {
    category = "AZFWThreatIntel"
  }

  # IDPS logs (Premium SKU only)
  dynamic "enabled_log" {
    for_each = var.azfw_tier == "Premium" ? [1] : []
    content {
      category = "AZFWIdpsSignature"
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Alerts for Threat Intelligence Hits
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "threat_intel_alert" {
  count               = var.firewall_type == "azfw" && var.enable_firewall_threat_intel && var.enable_threat_intel_alerts ? 1 : 0
  name                = "alert-azfw-threatintel-${var.region_code}-${var.environment}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  description         = "Alert when Azure Firewall blocks threats via Threat Intelligence"
  enabled             = true
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [var.log_analytics_workspace_id]
  severity             = 2  # Warning

  criteria {
    query                   = <<-QUERY
      AzureDiagnostics
      | where Category == "AZFWThreatIntel"
      | where ThreatLevel_s in ("High", "Medium")
      | summarize ThreatCount = count() by SourceIP = SourceIP_s, ThreatLevel = ThreatLevel_s, ThreatDescription = msg_s
      | where ThreatCount > 0
    QUERY
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"

    dimension {
      name     = "SourceIP"
      operator = "Include"
      values   = ["*"]
    }

    dimension {
      name     = "ThreatLevel"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = var.security_action_group_ids
  }

  tags = var.tags
}

# Outputs
output "firewall_policy_id" {
  description = "ID of the Azure Firewall Policy"
  value       = var.enable_firewall_threat_intel ? azurerm_firewall_policy.hub[0].id : null
}

output "firewall_threat_intel_mode" {
  description = "Threat Intelligence mode configured"
  value       = var.enable_firewall_threat_intel ? var.firewall_threat_intel_mode : "Disabled"
}

output "firewall_idps_mode" {
  description = "IDPS mode configured (Premium SKU only)"
  value       = var.azfw_tier == "Premium" && var.enable_firewall_threat_intel ? var.firewall_idps_mode : "Not Available"
}

output "firewall_diagnostics_enabled" {
  description = "Whether threat intelligence diagnostics are enabled"
  value       = var.enable_firewall_threat_intel
}
