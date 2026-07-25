output "policy_assignments" {
  description = "Map of policy assignment IDs"
  value = {
    require_tags          = azurerm_management_group_policy_assignment.require_tags_root.id
    allowed_locations     = azurerm_management_group_policy_assignment.allowed_locations.id
    nsg_on_subnets       = azurerm_management_group_policy_assignment.nsg_on_subnets.id
    sandbox_env_tag      = azurerm_management_group_policy_assignment.sandbox_tag.id
    sandbox_expiry       = azurerm_management_group_policy_assignment.sandbox_expiry.id
    deny_sandbox_peering = azurerm_management_group_policy_assignment.deny_sandbox_peering.id
  }
}
