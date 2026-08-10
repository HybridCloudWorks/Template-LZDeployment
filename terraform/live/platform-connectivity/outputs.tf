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

# Blob private DNS zone for the workload layers' flow-log private endpoints
# (TODO item 2.10). Unconditional, like management_workspace above, so the
# workload layers' remote-state read always finds the key; the value is an
# empty string until deploy_private_dns_zones is flipped, and the workload
# layers treat empty as "no endpoint" rather than needing a second flag.
output "blob_private_dns_zone_id" {
  # Looked up by NAME in the created set rather than by position, because the
  # set is now the client's list (TODO item 2.12) and need not contain the blob
  # zone at all. A client who replaced the default list with, say, only
  # privatelink.vaultcore.azure.net gets an empty string here and their
  # flow-log endpoints correctly stay off, rather than an index error at plan
  # or an endpoint bound to the wrong zone.
  description = "Resource ID of the privatelink.blob.core.windows.net private DNS zone, or an empty string when the zones are not deployed or the blob zone is not among them."
  value       = try(azurerm_private_dns_zone.blob[local.blob_zone_name].id, "")
}

output "private_dns_zone_ids" {
  description = "Map of every created private DNS zone name to its resource ID. Empty when deploy_private_dns_zones is false."
  value       = { for name, z in azurerm_private_dns_zone.blob : name => z.id }
}
