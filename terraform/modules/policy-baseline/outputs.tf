output "policy_assignments" {
  description = "Map of policy assignment IDs"
  value = {
    require_tags         = azurerm_management_group_policy_assignment.require_tags_root.id
    allowed_locations    = azurerm_management_group_policy_assignment.allowed_locations.id
    nsg_on_subnets       = azurerm_management_group_policy_assignment.nsg_on_subnets.id
    sandbox_env_tag      = azurerm_management_group_policy_assignment.sandbox_tag.id
    sandbox_expiry       = azurerm_management_group_policy_assignment.sandbox_expiry.id
    deny_sandbox_peering = azurerm_management_group_policy_assignment.deny_sandbox_peering.id
  }
}

output "tls_policy_initiative_id" {
  description = "ID of the TLS 1.2 enforcement policy initiative"
  value       = azurerm_policy_set_definition.tls_12_enforcement.id
}

output "tls_policy_assignment_id" {
  description = "ID of the TLS 1.2 policy assignment"
  value       = azurerm_management_group_policy_assignment.tls_12_root.id
}

output "policy_definitions" {
  description = "Map of all TLS 1.2 policy definitions"
  value = {
    storage_tls_12     = azurerm_policy_definition.enforce_storage_tls_12.id
    appservice_tls_12  = azurerm_policy_definition.enforce_appservice_tls_12.id
    functionapp_tls_12 = azurerm_policy_definition.enforce_functionapp_tls_12.id
    mysql_tls_12       = azurerm_policy_definition.enforce_mysql_tls_12.id
    postgresql_tls_12  = azurerm_policy_definition.enforce_postgresql_tls_12.id
    apim_tls_12        = azurerm_policy_definition.enforce_apim_tls_12.id
  }
}
