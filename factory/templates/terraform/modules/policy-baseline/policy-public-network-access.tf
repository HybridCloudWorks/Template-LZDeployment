# Azure Policy: public network access on PaaS data services
#
# The wizard has collected connectivity.privateEndpoints.denyPublicNetworkAccessPolicy
# since the factory shipped and nothing consumed it (TODO item 2.14). This is
# the assignment behind that answer.
#
# WHY CUSTOM DEFINITIONS RATHER THAN THE BUILT-INS: the module already writes
# its own definitions for exactly this shape of rule (see policy-tls-minimum.tf),
# and a custom definition carries its own parameterised effect rather than
# depending on a built-in GUID whose allowed effects can change under us. The
# trade is that this covers the PaaS services a landing zone actually acquires
# — storage accounts and key vaults — and not the ~20 services the ALZ
# Deny-Public-Endpoints initiative reaches. Adding a service is one more
# definition and one more reference in the set below.
#
# WHY THE DEFAULT EFFECT IS Audit, NOT Deny:
# this estate creates storage accounts that deliberately keep public network
# access ENABLED and rely on network rules instead — the flow-log accounts
# (terraform/modules/nsg-flow-logs/main.tf, public_network_access_enabled =
# true with default_action = "Deny") and the Terraform state account during
# setup. A Deny assignment at landing-zone scope would make the first apply of
# a generated repository fail on the estate's own resources, which is the
# failure mode decision 0009 was written to prevent. Audit surfaces the posture
# in compliance immediately and costs nothing; tighten public_network_access_effect
# to Deny in a PR once the estate's own accounts are behind private endpoints.
#
# SCOPE IS LANDING ZONES, NOT ROOT: the platform management group holds the
# state storage account, which cannot be private-endpoint-only during
# bootstrap — the client's own machine has to reach it to create the estate
# (decision 0004). Assigning at root would sweep it in.

resource "azurerm_policy_definition" "storage_public_network_access" {
  count = var.assign_public_network_access_policy ? 1 : 0

  name         = "storage-public-network-access"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Storage accounts should disable public network access"
  description  = "Storage accounts should be reachable only through private endpoints. Effect is parameterised; the landing zone assigns Audit until the platform's own accounts are private-endpoint-only."

  metadata = jsonencode({
    category = "Storage"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Storage/storageAccounts"
        },
        {
          # Absent counts as non-compliant: the property defaults to Enabled
          # when omitted, so a rule that only caught the explicit value would
          # miss every account that never set it.
          anyOf = [
            {
              field  = "Microsoft.Storage/storageAccounts/publicNetworkAccess"
              exists = false
            },
            {
              field     = "Microsoft.Storage/storageAccounts/publicNetworkAccess"
              notEquals = "Disabled"
            }
          ]
        }
      ]
    }
    then = {
      effect = "[parameters('effect')]"
    }
  })

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Enable or disable the execution of the policy"
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
  })
}

resource "azurerm_policy_definition" "keyvault_public_network_access" {
  count = var.assign_public_network_access_policy ? 1 : 0

  name         = "keyvault-public-network-access"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Key vaults should disable public network access"
  description  = "Key vaults should be reachable only through private endpoints. Effect is parameterised to match the storage rule."

  metadata = jsonencode({
    category = "Key Vault"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.KeyVault/vaults"
        },
        {
          anyOf = [
            {
              field  = "Microsoft.KeyVault/vaults/publicNetworkAccess"
              exists = false
            },
            {
              field     = "Microsoft.KeyVault/vaults/publicNetworkAccess"
              notEquals = "Disabled"
            }
          ]
        }
      ]
    }
    then = {
      effect = "[parameters('effect')]"
    }
  })

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Enable or disable the execution of the policy"
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
  })
}

# One initiative so the effect is set once and both rules move together. A
# client tightening to Deny should not be able to half-apply it.
resource "azurerm_policy_set_definition" "public_network_access" {
  count = var.assign_public_network_access_policy ? 1 : 0

  name         = "public-network-access-baseline"
  policy_type  = "Custom"
  display_name = "PaaS data services should disable public network access"
  description  = "Groups the storage and key vault public-network-access rules so one effect governs both."

  metadata = jsonencode({
    category = "Network"
    version  = "1.0.0"
  })

  parameters = jsonencode({
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Effect applied by every rule in this initiative"
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
  })

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.storage_public_network_access[0].id
    reference_id         = "storagePublicNetworkAccess"
    parameter_values = jsonencode({
      effect = { value = "[parameters('effect')]" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.keyvault_public_network_access[0].id
    reference_id         = "keyVaultPublicNetworkAccess"
    parameter_values = jsonencode({
      effect = { value = "[parameters('effect')]" }
    })
  }
}

resource "azurerm_management_group_policy_assignment" "public_network_access" {
  count = var.assign_public_network_access_policy ? 1 : 0

  name                 = "public-network-access"
  management_group_id  = var.landingzones_mg_id
  policy_definition_id = azurerm_policy_set_definition.public_network_access[0].id
  display_name         = "PaaS data services should disable public network access"
  description          = "Audits (or denies) storage accounts and key vaults reachable from the public internet."

  # No identity block: Audit and Deny evaluate in-line and need no managed
  # identity. Adding one would also force a location on this assignment for a
  # remediation that never runs.

  parameters = jsonencode({
    effect = {
      value = var.public_network_access_effect
    }
  })

  non_compliance_message {
    content = "PaaS data services must disable public network access and be reached through a private endpoint."
  }
}
