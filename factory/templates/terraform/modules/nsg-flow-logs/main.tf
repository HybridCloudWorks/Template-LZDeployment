# NSG Flow Logs + Traffic Analytics Module
# Phase 2 - Task 5.2: Enable comprehensive network monitoring

# Storage Account for Flow Logs
resource "azurerm_storage_account" "flow_logs" {
  # ── Accepted checkov findings (TODO item 2.15) ──────────────────────────
  # Each of these defers to a decision already taken and written down. They
  # are suppressed here, at the resource, rather than in a config file.
  #
  #checkov:skip=CKV_AZURE_59:Public network access is deliberately enabled and fronted by the network rules below (default_action Deny + trusted-services bypass). Network Watcher writes flow logs through the service, and closing this without a private endpoint breaks that. Decision 0009; the endpoint itself is TODO 2.11/2.14.
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys need the keyvault-cmk module, which is a decided deferral (TODO item 2.4, render-blocked by guard G03). Service-managed encryption is on.
  #checkov:skip=CKV2_AZURE_41:The sas_policy block IS configured below (1-hour expiration, Log action) - this is not a missing control. Checkov still reports it: CKV2_* are graph checks, and this resource lives inside a module whose graph checkov did not resolve here (its guidelines endpoint is also unreachable in this environment). Suppressed as a scanner miss, with the control present and reviewable a few lines down.
  #checkov:skip=CKV_AZURE_43:The name is composed from variables checkov cannot resolve, so it evaluates the unresolved expression rather than the 21-character lowercase result. The module validates the real name itself.
  #checkov:skip=CKV_AZURE_33:Queue-service logging cannot be enabled for a service this account never uses - flow logs are blobs only. Enabling it would create a queue endpoint to log.
  #checkov:skip=CKV2_AZURE_40:Shared-key authorization must stay ENABLED here, unlike the state account. NSG flow logs authenticate to this account with its ACCESS KEYS - Microsoft documents that rotating them stops flow logs until the feature is disabled and re-enabled ("Self-managed key rotation", azure-docs articles/network-watcher/nsg-flow-logs-overview.md, Storage account requirements). Disabling shared-key access therefore breaks flow-log delivery outright. Settled 2026-08-10; TODO item 2.17 closed.

  # CKV2_AZURE_41. Nothing here issues a SAS — flow logs are written by the
  # Network Watcher service and read through AAD — but an expiration policy
  # bounds any SAS an operator later mints by hand, which is exactly the case
  # worth bounding (TODO item 2.15).
  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  # Storage account names are globally unique, so the composed fallback below
  # allows only ONE instance of this module per (region, environment) across
  # the whole estate. A caller that needs a second instance in the same region
  # and environment — the connectivity layer's hub fw_mgmt coverage is the
  # first — must supply storage_account_name explicitly (contract 8a). The
  # fallback is unchanged from before the override existed, so every existing
  # caller renders the same name it always did.
  name                     = coalesce(var.storage_account_name, local.default_storage_account_name)
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"

  # Security settings. Public network access stays ENABLED because the NSG
  # flow-log writer is a platform service that must reach the account through
  # its public endpoint; access is still constrained by the deny-by-default
  # network rules below (trusted-services bypass plus explicit allowances).
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

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

    # Explicit public ranges, parsed fail-closed (see locals below)
    ip_rules = local.flow_logs_ip_rules
  }

  tags = merge(
    var.tags,
    {
      purpose   = "nsg-flow-logs"
      component = "monitoring"
    }
  )
}

locals {
  # The name this module has always composed, kept as the fallback so callers
  # that supply no override are byte-identical to the pre-override module. It
  # satisfies the same rule var.storage_account_name validates against —
  # "stflowlogs" is 10 lowercase letters, region codes are 2–5 lowercase
  # characters (schema $defs/regionCode) and environment names are short
  # lowercase words, so the result stays inside 3–24 lowercase alphanumerics.
  default_storage_account_name = "stflowlogs${var.region_code}${var.environment}"

  # Azure storage ip_rules accept public IPv4 addresses or CIDR ranges, with
  # /32 written as a bare address. The parser fails closed: an entry that does
  # not parse as an IPv4 CIDR is dropped, narrowing access instead of
  # widening it, and an empty result leaves default_action = "Deny" in force.
  flow_logs_ip_rules = [
    for c in var.allowed_ip_cidrs :
    (endswith(c, "/32") ? split("/", c)[0] : c)
    if can(cidrhost(c, 0)) && !strcontains(c, ":")
  ]
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

  # enable_private_endpoint defaults to TRUE while both values it needs default
  # to empty, so a caller that flips it on and supplies neither gets the quiet
  # failure this repo exists to prevent: an empty subnet_id is rejected only at
  # apply, and an empty zone group creates a private endpoint whose name never
  # resolves. Fail at plan instead (TODO item 2.10).
  lifecycle {
    precondition {
      condition     = var.private_endpoint_subnet_id != ""
      error_message = "enable_private_endpoint = true requires private_endpoint_subnet_id."
    }
    precondition {
      condition     = length(var.private_dns_zone_ids) > 0
      error_message = "enable_private_endpoint = true requires at least one private_dns_zone_ids entry — a privatelink.blob.core.windows.net zone linked to the VNet holding private_endpoint_subnet_id."
    }
  }
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
  target_resource_id   = each.value
  storage_account_id   = azurerm_storage_account.flow_logs.id
  enabled              = true
  version              = 2 # Version 2 provides more detailed flow information

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

# Diagnostic Settings for the storage account's blob service. Log category
# groups only exist on the blobServices sub-resource; the account level
# exposes metrics alone.
resource "azurerm_monitor_diagnostic_setting" "flow_logs_storage" {
  name                       = "diag-flowlogs-storage-${var.environment}"
  target_resource_id         = "${azurerm_storage_account.flow_logs.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_resource_id

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
  severity             = 2 # Warning

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
  severity             = 1 # Error

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

