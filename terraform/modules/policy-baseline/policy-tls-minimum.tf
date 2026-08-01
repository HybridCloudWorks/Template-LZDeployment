# Azure Policy: Enforce TLS 1.2 Minimum Version
# Ensures all Azure services use TLS 1.2 or higher for secure communications
# Applies to: Storage Accounts, App Services, Function Apps, API Management, Azure Database services

# Policy Definition: Enforce TLS 1.2 for Storage Accounts
resource "azurerm_policy_definition" "enforce_storage_tls_12" {
  name         = "enforce-storage-tls-12"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Storage accounts should use TLS 1.2 or higher"
  description  = "Enforce TLS 1.2 minimum version for Azure Storage accounts to ensure secure data transfer"

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
          anyOf = [
            {
              field  = "Microsoft.Storage/storageAccounts/minimumTlsVersion"
              exists = false
            },
            {
              field     = "Microsoft.Storage/storageAccounts/minimumTlsVersion"
              notEquals = "TLS1_2"
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
      defaultValue  = "Deny"
    }
  })
}

# Policy Definition: Enforce TLS 1.2 for App Services
# Targets the sites/config sub-resource: minTlsVersion lives on
# Microsoft.Web/sites/config, not on the site resource itself, so a policy
# aimed at Microsoft.Web/sites never evaluates it.
# Mode is "All" because sites/config is not a taggable resource type and
# Indexed policies skip it entirely.
resource "azurerm_policy_definition" "enforce_appservice_tls_12" {
  name         = "enforce-appservice-tls-12"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "App Service should use TLS 1.2 or higher"
  description  = "Enforce TLS 1.2 minimum version for Azure App Service to ensure secure connections"

  metadata = jsonencode({
    category = "App Service"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Web/sites/config"
        },
        {
          anyOf = [
            {
              # Alias verified against Microsoft's built-in policy
              # RequireLatestTls_WebApp_Audit.json, which evaluates this same
              # field. "less" (not notEquals) so TLS 1.3 stays compliant.
              field  = "Microsoft.Web/sites/config/minTlsVersion"
              exists = false
            },
            {
              field = "Microsoft.Web/sites/config/minTlsVersion"
              less  = "1.2"
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
      defaultValue  = "Deny"
    }
  })
}

# Policy Definition: Enforce TLS 1.2 for Function Apps
# Same sites/config targeting and "All" mode rationale as the App Service
# definition above.
resource "azurerm_policy_definition" "enforce_functionapp_tls_12" {
  name         = "enforce-functionapp-tls-12"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Function Apps should use TLS 1.2 or higher"
  description  = "Enforce TLS 1.2 minimum version for Azure Function Apps to ensure secure connections"

  metadata = jsonencode({
    category = "App Service"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Web/sites/config"
        },
        {
          field = "kind"
          like  = "functionapp*"
        },
        {
          anyOf = [
            {
              # Alias verified against Microsoft's built-in policy
              # RequireLatestTls_WebApp_Audit.json, which evaluates this same
              # field. "less" (not notEquals) so TLS 1.3 stays compliant.
              field  = "Microsoft.Web/sites/config/minTlsVersion"
              exists = false
            },
            {
              field = "Microsoft.Web/sites/config/minTlsVersion"
              less  = "1.2"
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
      defaultValue  = "Deny"
    }
  })
}

# Policy Definition: Enforce TLS 1.2 for Azure Database for MySQL
resource "azurerm_policy_definition" "enforce_mysql_tls_12" {
  name         = "enforce-mysql-tls-12"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Azure Database for MySQL should use TLS 1.2 or higher"
  description  = "Enforce TLS 1.2 minimum version for Azure Database for MySQL"

  metadata = jsonencode({
    category = "SQL"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.DBforMySQL/servers"
        },
        {
          anyOf = [
            {
              field  = "Microsoft.DBforMySQL/servers/minimalTlsVersion"
              exists = false
            },
            {
              field     = "Microsoft.DBforMySQL/servers/minimalTlsVersion"
              notEquals = "TLS1_2"
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
      defaultValue  = "Deny"
    }
  })
}

# Policy Definition: Enforce TLS 1.2 for Azure Database for PostgreSQL
resource "azurerm_policy_definition" "enforce_postgresql_tls_12" {
  name         = "enforce-postgresql-tls-12"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Azure Database for PostgreSQL should use TLS 1.2 or higher"
  description  = "Enforce TLS 1.2 minimum version for Azure Database for PostgreSQL"

  metadata = jsonencode({
    category = "SQL"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.DBforPostgreSQL/servers"
        },
        {
          anyOf = [
            {
              field  = "Microsoft.DBforPostgreSQL/servers/minimalTlsVersion"
              exists = false
            },
            {
              field     = "Microsoft.DBforPostgreSQL/servers/minimalTlsVersion"
              notEquals = "TLS1_2"
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
      defaultValue  = "Deny"
    }
  })
}

# Policy Initiative: TLS 1.2 Enforcement Bundle
resource "azurerm_policy_set_definition" "tls_12_enforcement" {
  name         = "tls-12-enforcement-initiative"
  policy_type  = "Custom"
  display_name = "Enforce TLS 1.2 Across All Services"
  description  = "Policy initiative to enforce TLS 1.2 minimum version across Storage, App Services, Function Apps, and Database services"

  metadata = jsonencode({
    category = "Security"
    version  = "1.0.0"
  })

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_storage_tls_12.id
    reference_id         = "StorageTLS12"
    parameter_values = jsonencode({
      effect = { value = "Deny" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_appservice_tls_12.id
    reference_id         = "AppServiceTLS12"
    parameter_values = jsonencode({
      effect = { value = "Deny" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_functionapp_tls_12.id
    reference_id         = "FunctionAppTLS12"
    parameter_values = jsonencode({
      effect = { value = "Deny" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_mysql_tls_12.id
    reference_id         = "MySQLTLS12"
    parameter_values = jsonencode({
      effect = { value = "Deny" }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.enforce_postgresql_tls_12.id
    reference_id         = "PostgreSQLTLS12"
    parameter_values = jsonencode({
      effect = { value = "Deny" }
    })
  }
}

# Policy Assignment: Apply to Root Management Group
resource "azurerm_management_group_policy_assignment" "tls_12_root" {
  name                 = "tls-12-enforcement"
  management_group_id  = var.root_mg_id
  policy_definition_id = azurerm_policy_set_definition.tls_12_enforcement.id
  display_name         = "Enforce TLS 1.2 Minimum Version"
  description          = "Enforces TLS 1.2 minimum version across all Azure services in the organization"
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  non_compliance_message {
    content = "Resources must use TLS 1.2 or higher. TLS 1.0 and TLS 1.1 are deprecated and insecure."
  }
}
