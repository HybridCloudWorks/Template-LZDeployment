# NSG Flow Logs + Traffic Analytics Module
# Phase 2 - Task 5.2: Enable comprehensive network monitoring

# Storage Account for Flow Logs
resource "azurerm_storage_account" "flow_logs" {
  name                     = "stflowlogs${var.region_code}${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "RAGZRS"  # Geo-redundant for compliance
  min_tls_version          = "TLS1_2"
  
  # Security settings
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  
  # Blob properties
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = var.flow_log_retention_days
    }
    
    container_delete_retention_policy {
      days = var.flow_log_retention_days
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    
    # Allow access from management subnet
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = merge(
    var.tags,
    {
      purpose   = "nsg-flow-logs"
      component = "monitoring"
    }
  )
}

# Private Endpoint for Storage Account
resource "azurerm_private_endpoint" "flow_logs_blob" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "pe-flowlogs-blob-${var.region_code}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-flowlogs-blob"
    private_connection_resource_id = azurerm_storage_account.flow_logs.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdz-group-blob"
    private_dns_zone_ids = var.private_dns_zone_ids
  }

  tags = var.tags
}

# Network Watcher (usually already exists per region, but ensure it's present)
data "azurerm_network_watcher" "main" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

# NSG Flow Logs for each provided NSG
resource "azurerm_network_watcher_flow_log" "nsg_flow_logs" {
  for_each = var.nsg_ids

  name                 = "fl-${each.key}-${var.environment}"
  network_watcher_name = data.azurerm_network_watcher.main.name
  resource_group_name  = data.azurerm_network_watcher.main.resource_group_name
  target_resource_id     = each.value
  storage_account_id   = azurerm_storage_account.flow_logs.id
  enabled              = true
  version              = 2  # Version 2 provides more detailed flow information

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  # Traffic Analytics
  traffic_analytics {
    enabled               = var.enable_traffic_analytics
    workspace_id          = var.log_analytics_workspace_id
    workspace_region      = var.log_analytics_workspace_region
    workspace_resource_id = var.log_analytics_workspace_resource_id
    interval_in_minutes   = var.traffic_analytics_interval
  }

  tags = merge(
    var.tags,
    {
      nsg_name = each.key
    }
  )
}

# Diagnostic Settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "flow_logs_storage" {
  name                       = "diag-flowlogs-storage-${var.environment}"
  target_resource_id         = azurerm_storage_account.flow_logs.id
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

  enabled_log {
    category_group = "audit"
  }

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Alerts for unusual traffic patterns
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_traffic_alert" {
  count               = var.enable_traffic_analytics && var.enable_traffic_alerts ? 1 : 0
  name                = "alert-high-network-traffic-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert when network traffic exceeds threshold"
  enabled             = true
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [var.log_analytics_workspace_resource_id]
  severity             = 2  # Warning

  criteria {
    query                   = <<-QUERY
      AzureNetworkAnalytics_CL
      | where SubType_s == "FlowLog"
      | summarize TotalBytes = sum(toint(BytesSent_d) + toint(BytesReceived_d)) by SourceIP = SrcIP_s
      | where TotalBytes > ${var.high_traffic_threshold_gb * 1024 * 1024 * 1024}
    QUERY
    time_aggregation_method = "Total"
    threshold               = 1
    operator                = "GreaterThan"

    dimension {
      name     = "SourceIP"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = var.action_group_ids
  }

  tags = var.tags
}

# Alert for denied traffic spikes (potential security issue)
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "denied_traffic_alert" {
  count               = var.enable_traffic_analytics && var.enable_traffic_alerts ? 1 : 0
  name                = "alert-denied-traffic-spike-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert when denied traffic exceeds threshold (potential attack)"
  enabled             = true
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [var.log_analytics_workspace_resource_id]
  severity             = 1  # Error

  criteria {
    query                   = <<-QUERY
      AzureNetworkAnalytics_CL
      | where SubType_s == "FlowLog"
      | where FlowStatus_s == "D"  // Denied flows
      | summarize DeniedFlows = count() by SourceIP = SrcIP_s, DestPort = DestPort_d
      | where DeniedFlows > ${var.denied_traffic_threshold}
    QUERY
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"

    dimension {
      name     = "SourceIP"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_groups = var.action_group_ids
  }

  tags = var.tags
}

output "next_steps" {
  description = "Next steps after enabling NSG Flow Logs"
  value       = <<-EOT
    NSG Flow Logs + Traffic Analytics Enabled:
    
    ✅ Flow logs enabled for ${length(var.nsg_ids)} NSG(s)
    ✅ Storage: ${azurerm_storage_account.flow_logs.name} (RAGZRS, ${var.flow_log_retention_days} day retention)
    ✅ Traffic Analytics: ${var.enable_traffic_analytics ? "Enabled" : "Disabled"}
    
    Next Steps:
    1. View Traffic Analytics dashboard in Azure Portal:
       Navigate to Log Analytics workspace → Traffic Analytics
    
    2. Query flow logs with KQL:
       AzureNetworkAnalytics_CL
       | where SubType_s == "FlowLog"
       | summarize FlowCount = count() by SrcIP_s, DestIP_s, DestPort_d
    
    3. Configure additional alerts for security monitoring
    
    4. Review denied flows for security threats:
       AzureNetworkAnalytics_CL
       | where FlowStatus_s == "D"
       | project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d, NSGRuleName_s
    
    Monthly Cost: ~$${var.flow_log_retention_days * length(var.nsg_ids) * 0.15 + (var.enable_traffic_analytics ? 100 : 0)}
  EOT
}
