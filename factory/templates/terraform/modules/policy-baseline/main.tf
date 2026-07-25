# Policy Baseline Module
# Deploys Azure Policy definitions and assignments

# Require specific tags policy
resource "azurerm_policy_definition" "require_tags" {
  name         = "require-mandatory-tags"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require mandatory tags"
  description  = "Enforces required tags: owner, application, environment, cost_center"
  
  metadata = jsonencode({
    category = "Tags"
  })
  
  policy_rule = jsonencode({
    if = {
      anyOf = [
        {
          field  = "tags['owner']"
          exists = false
        },
        {
          field  = "tags['application']"
          exists = false
        },
        {
          field  = "tags['environment']"
          exists = false
        },
        {
          field  = "tags['cost_center']"
          exists = false
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

# Assign require tags at root
resource "azurerm_management_group_policy_assignment" "require_tags_root" {
  name                 = "require-tags"
  management_group_id  = var.root_mg_id
  policy_definition_id = azurerm_policy_definition.require_tags.id
  display_name         = "Require mandatory tags"
  description          = "Enforces owner, application, environment, cost_center tags"
}

# Allowed locations policy
resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  management_group_id  = var.root_mg_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  display_name         = "Allowed locations"
  description          = "Restricts deployment to approved regions"
  
  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}

# NSG on subnets policy
resource "azurerm_management_group_policy_assignment" "nsg_on_subnets" {
  name                 = "nsg-on-subnets"
  management_group_id  = var.platform_mg_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e71308d3-144b-4262-b144-efdc3cc90517"
  display_name         = "NSG should be associated with subnets"
  description          = "Audits subnets without NSGs"
}

# Sandbox environment tag enforcement
resource "azurerm_policy_definition" "sandbox_environment_tag" {
  name         = "enforce-sandbox-environment-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Enforce environment=sandbox in Sandbox subscription"
  description  = "Denies resources in Sandbox MG that don't have environment=sandbox"
  
  metadata = jsonencode({
    category = "Tags"
  })
  
  policy_rule = jsonencode({
    if = {
      not = {
        field  = "tags['environment']"
        equals = "sandbox"
      }
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "sandbox_tag" {
  name                 = "sandbox-env-tag"
  management_group_id  = var.sandbox_mg_id
  policy_definition_id = azurerm_policy_definition.sandbox_environment_tag.id
  display_name         = "Enforce environment=sandbox"
}

# Sandbox expiry date tag requirement
resource "azurerm_policy_definition" "sandbox_expiry_tag" {
  name         = "require-sandbox-expiry-tag"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Require expiry_date tag in Sandbox"
  description  = "Requires expiry_date tag on all Sandbox resources"
  
  metadata = jsonencode({
    category = "Tags"
  })
  
  policy_rule = jsonencode({
    if = {
      field  = "tags['expiry_date']"
      exists = false
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "sandbox_expiry" {
  name                 = "sandbox-expiry-tag"
  management_group_id  = var.sandbox_mg_id
  policy_definition_id = azurerm_policy_definition.sandbox_expiry_tag.id
  display_name         = "Require expiry_date tag"
}

# Deny VNet peering in Sandbox (air-gap enforcement)
resource "azurerm_policy_definition" "deny_sandbox_peering" {
  name         = "deny-sandbox-vnet-peering"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny VNet peering in Sandbox"
  description  = "Prevents VNet peering to maintain Sandbox air-gap"
  
  metadata = jsonencode({
    category = "Network"
  })
  
  policy_rule = jsonencode({
    if = {
      field = "type"
      equals = "Microsoft.Network/virtualNetworks/virtualNetworkPeerings"
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_sandbox_peering" {
  name                 = "deny-peering"
  management_group_id  = var.sandbox_mg_id
  policy_definition_id = azurerm_policy_definition.deny_sandbox_peering.id
  display_name         = "Deny VNet peering"
}
