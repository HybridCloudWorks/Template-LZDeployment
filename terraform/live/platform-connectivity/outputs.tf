output "primary_hub_vnet_id" {
  description = "Primary hub VNet ID"
  value       = module.hub_primary.hub_vnet_id
}

output "primary_hub_firewall_ip" {
  description = "Primary hub firewall private IP"
  value       = module.hub_primary.firewall_private_ip
}

output "dr_hub_vnet_id" {
  description = "DR hub VNet ID"
  value       = module.hub_dr.hub_vnet_id
}

output "dr_hub_firewall_ip" {
  description = "DR hub firewall private IP"
  value       = module.hub_dr.firewall_private_ip
}

output "primary_hub_details" {
  description = "Primary hub details for spoke deployments"
  value = {
    vnet_id             = module.hub_primary.hub_vnet_id
    vnet_name           = module.hub_primary.hub_vnet_name
    resource_group_name = module.hub_primary.resource_group_name
    firewall_private_ip = module.hub_primary.firewall_private_ip
  }
}

output "dr_hub_details" {
  description = "DR hub details for spoke deployments"
  value = {
    vnet_id             = module.hub_dr.hub_vnet_id
    vnet_name           = module.hub_dr.hub_vnet_name
    resource_group_name = module.hub_dr.resource_group_name
    firewall_private_ip = module.hub_dr.firewall_private_ip
  }
}

# Workspace triple for the workload layers' NSG flow-log calls. Unconditional
# so the workload layers' remote-state read always finds it; the values are
# empty strings until wire_management_workspace is flipped.
output "management_workspace" {
  description = "Central Log Analytics workspace facts required by NSG flow-log Traffic Analytics (ARM resource ID, short GUID, region). Empty until wire_management_workspace is enabled."
  value       = local.management_workspace
}
