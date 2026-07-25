# Management Groups Module
# Creates the management group hierarchy

# Root management group
resource "azurerm_management_group" "root" {
  display_name = "mg-${var.org_prefix}-root"
  name         = "mg-${var.org_prefix}-root"
}

# Platform management group
resource "azurerm_management_group" "platform" {
  display_name               = "mg-${var.org_prefix}-platform"
  name                       = "mg-${var.org_prefix}-platform"
  parent_management_group_id = azurerm_management_group.root.id
}

# Landing Zones management group
resource "azurerm_management_group" "landingzones" {
  display_name               = "mg-${var.org_prefix}-landingzones"
  name                       = "mg-${var.org_prefix}-landingzones"
  parent_management_group_id = azurerm_management_group.root.id
}

# Sandbox management group
resource "azurerm_management_group" "sandbox" {
  display_name               = "mg-${var.org_prefix}-sandbox"
  name                       = "mg-${var.org_prefix}-sandbox"
  parent_management_group_id = azurerm_management_group.root.id
}

# Move subscriptions into management groups
resource "azurerm_management_group_subscription_association" "identity" {
  count                = var.identity_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.platform.id
  subscription_id      = "/subscriptions/${var.identity_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "connectivity" {
  count                = var.connectivity_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.platform.id
  subscription_id      = "/subscriptions/${var.connectivity_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "management" {
  count                = var.management_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.platform.id
  subscription_id      = "/subscriptions/${var.management_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "workload_prod" {
  count                = var.workload_prod_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.landingzones.id
  subscription_id      = "/subscriptions/${var.workload_prod_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "workload_nonprod" {
  count                = var.workload_nonprod_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.landingzones.id
  subscription_id      = "/subscriptions/${var.workload_nonprod_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "sandbox" {
  count                = var.sandbox_subscription_id != "" ? 1 : 0
  management_group_id  = azurerm_management_group.sandbox.id
  subscription_id      = "/subscriptions/${var.sandbox_subscription_id}"
}
