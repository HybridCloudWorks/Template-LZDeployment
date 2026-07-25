# Management Baseline Module
# Provides Log Analytics, Automation Account, and monitoring foundations

data "azurerm_client_config" "current" {}

# Management Resource Group
resource "azurerm_resource_group" "management" {
  name     = "rg-${var.org_prefix}-management"
  location = var.location
  tags     = var.tags
}

# Log Analytics Workspace - Central logging hub
resource "azurerm_log_analytics_workspace" "alz" {
  name                = "law-${var.org_prefix}-${var.region_code}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# Automation Account - For operational management and runbooks
resource "azurerm_automation_account" "alz" {
  name                = "aa-${var.org_prefix}-${var.region_code}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  sku_name            = "Basic"

  tags = var.tags
}

# Application Insights - For application-level monitoring
resource "azurerm_application_insights" "alz" {
  name                = "appi-${var.org_prefix}-${var.region_code}"
  location            = azurerm_resource_group.management.location
  resource_group_name = azurerm_resource_group.management.name
  application_type    = "other"
  workspace_id        = azurerm_log_analytics_workspace.alz.id

  tags = var.tags
}

# Action Group - For alert notifications
resource "azurerm_monitor_action_group" "alz" {
  name                = "ag-${var.org_prefix}-${var.region_code}"
  resource_group_name = azurerm_resource_group.management.name
  short_name          = substr("alz-${var.org_prefix}", 0, 12)

  tags = var.tags
}

# Alert Rule - CPU > 80%
resource "azurerm_monitor_metric_alert" "cpu_high" {
  name                = "alert-cpu-${var.org_prefix}"
  resource_group_name = azurerm_resource_group.management.name
  scopes              = [azurerm_log_analytics_workspace.alz.id]
  description         = "Alert when workspace ingestion volume exceeds threshold"
  severity            = 2
  enabled             = true
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_name      = "Data Ingestion"
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.alz.id
  }
}
