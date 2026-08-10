# Platform Connectivity - Dual-Region Hubs
# Deploy after global layer

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  backend "azurerm" {
    # Configuration provided via backend.hcl
  }
}

provider "azurerm" {
  features {}
  # Stated 5.0 default (decision 0006): the provider registers no resource
  # providers — the broker registers the required namespaces at bootstrap.
  subscription_id                 = var.connectivity_subscription_id
  resource_provider_registrations = "none"
}

# The central Log Analytics workspace is owned by platform-management, which
# keeps separate state (control AR3). Mirrors the corpus connectivity layer
# (decision 0003) so both trees carry the same mechanism: the read is
# count-gated on wire_management_workspace (default false) so a plan succeeds
# before platform-management has ever been applied — try() cannot rescue a
# provider read; only count works. Flip the boolean in a PR after that layer's
# first apply. Live uses one state container per layer with the key
# terraform.tfstate (contract #3); the corpus uses a shared container with
# per-layer keys, which is why the two reads are not byte-identical.
data "terraform_remote_state" "management" {
  count = var.wire_management_workspace ? 1 : 0

  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = "platform-management"
    key                  = "terraform.tfstate"
    # State storage disables shared keys; without AAD auth this read 403s.
    use_azuread_auth = true
  }
}

locals {
  common_tags = merge(var.default_tags, {
    layer = "platform-connectivity"
  })

  # Workspace ID precedence: an explicitly supplied variable wins; otherwise
  # the gated remote-state read; otherwise empty, which disables hub
  # diagnostics in the hub-network module.
  effective_law_id = (
    var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id :
    var.wire_management_workspace ? data.terraform_remote_state.management[0].outputs.log_analytics_workspace_id :
    ""
  )

  # The three facts NSG flow-log Traffic Analytics needs about the workspace,
  # re-exported below for the workload layers. Empty strings when the gate is
  # off — the workload layer's flow-log call is gated on its own boolean, so
  # empty values are never consumed.
  management_workspace = {
    resource_id = local.effective_law_id
    guid        = var.wire_management_workspace ? data.terraform_remote_state.management[0].outputs.log_analytics_workspace_guid : ""
    location    = var.wire_management_workspace ? data.terraform_remote_state.management[0].outputs.log_analytics_workspace_location : ""
  }
}

# Primary hub (South Central US)
module "hub_primary" {
  source = "../../modules/hub-network"

  region                     = var.primary_region
  region_code                = var.primary_region_code
  environment                = "prod"
  hub_address_space          = var.primary_hub_address_space
  firewall_type              = var.firewall_type
  azfw_tier                  = var.azfw_tier
  firewall_threat_intel_mode = var.firewall_threat_intel_mode
  nva_trust_ip_placeholder   = var.primary_nva_trust_ip
  deploy_bastion_placeholder = var.deploy_bastion
  deploy_dns_placeholder     = var.deploy_dns
  management_ip_ranges       = var.management_ip_ranges
  availability_zones         = var.primary_availability_zones
  log_analytics_workspace_id = local.effective_law_id
  tags                       = local.common_tags
}

# DR hub (North Central US)
module "hub_dr" {
  source = "../../modules/hub-network"

  region                     = var.dr_region
  region_code                = var.dr_region_code
  environment                = "prod"
  hub_address_space          = var.dr_hub_address_space
  firewall_type              = var.firewall_type
  azfw_tier                  = var.azfw_tier
  firewall_threat_intel_mode = var.firewall_threat_intel_mode
  nva_trust_ip_placeholder   = var.dr_nva_trust_ip
  deploy_bastion_placeholder = var.deploy_bastion
  deploy_dns_placeholder     = var.deploy_dns
  management_ip_ranges       = var.management_ip_ranges
  availability_zones         = var.dr_availability_zones
  log_analytics_workspace_id = local.effective_law_id
  tags                       = local.common_tags
}

# Global VNet peering between hubs
resource "azurerm_virtual_network_peering" "primary_to_dr" {
  name                         = "peer-hub-${var.primary_region_code}-to-${var.dr_region_code}"
  resource_group_name          = module.hub_primary.resource_group_name
  virtual_network_name         = module.hub_primary.hub_vnet_name
  remote_virtual_network_id    = module.hub_dr.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "dr_to_primary" {
  name                         = "peer-hub-${var.dr_region_code}-to-${var.primary_region_code}"
  resource_group_name          = module.hub_dr.resource_group_name
  virtual_network_name         = module.hub_dr.hub_vnet_name
  remote_virtual_network_id    = module.hub_primary.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Blob private DNS — decision 0009 follow-up (c), TODO item 2.10.
#
# A private endpoint without a matching private DNS zone resolves to nothing,
# which is why every flow-log caller in both trees has carried
# enable_private_endpoint = false since decision 0009. This is the zone those
# callers were waiting for.
#
# It lives HERE, not in the workload layers, for the reason the hub owns DNS
# generally: a private DNS zone is a global resource, one zone serves both
# regions and every spoke, and a per-workload-subscription zone would give the
# same name different contents depending on which VNet asked. The workload
# layers link their own spoke VNets to it across the subscription boundary
# using the hub-scoped provider alias they already hold for the hub side of
# VNet peering, and consume the ID from this layer's output.
#
# backend-bootstrap creates a zone of the same name in the state subscription.
# That is not a conflict: private DNS zone names are unique per resource group,
# not per tenant, and the two are linked to disjoint VNet sets — the bootstrap
# zone serves the state storage account's endpoint from the management VNet,
# this one serves the estate's spokes and hubs.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "blob" {
  count               = var.deploy_blob_private_dns_zone ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = module.hub_primary.resource_group_name

  tags = local.common_tags
}

# Both hubs link to the single zone. registration_enabled stays false on every
# link in this file: these VNets resolve privatelink records, they do not
# register their own VM names into the zone, and only one link per zone may
# enable registration at all.
resource "azurerm_private_dns_zone_virtual_network_link" "blob_hub_primary" {
  count = var.deploy_blob_private_dns_zone ? 1 : 0
  name  = "link-blob-hub-${var.primary_region_code}"
  # azurerm 5.0 requires private_dns_zone_id; resource_group_name +
  # private_dns_zone_name are rejected as unsupported (see backend-bootstrap).
  private_dns_zone_id  = azurerm_private_dns_zone.blob[0].id
  virtual_network_id   = module.hub_primary.hub_vnet_id
  registration_enabled = false

  tags = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_hub_dr" {
  count                = var.deploy_blob_private_dns_zone ? 1 : 0
  name                 = "link-blob-hub-${var.dr_region_code}"
  private_dns_zone_id  = azurerm_private_dns_zone.blob[0].id
  virtual_network_id   = module.hub_dr.hub_vnet_id
  registration_enabled = false

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# NSG flow logs for the hub — decision 0009 follow-up (b), TODO item 2.9.
#
# Network Watcher is regional AND per-subscription and the module reads it
# through the default provider, so the hub's fw_mgmt NSG can only be covered
# from this layer: the workload layers' instances cannot reach it, exactly as
# this layer cannot reach a spoke NSG.
#
# Each instance passes an EXPLICIT storage_account_name. workloads-prod
# creates stflowlogs<region_code>prod in these same two regions at the same
# environment, and storage account names are globally unique, so leaving these
# on the module's composed default would plan clean and then collide at apply
# (contract 8a). stflowlogshub<region_code>prod cannot collide with it: the
# literal segments differ, and no other caller in either tree composes a name
# beginning stflowlogshub.
#
# Gated on the NSG existing as well as on the flag. fw_mgmt is count-gated on
# an NVA firewall inside hub-network, so an azfw hub yields an empty nsg_ids
# map — creating the storage account anyway would bill for a flow-log pipeline
# with nothing to log.
#
# Flip enable_nsg_flow_logs in a PR only after (a) the hubs' first apply, so
# NetworkWatcherRG exists in the connectivity subscription — the module's
# Network Watcher read is a provider read that only count can gate — and (b)
# wire_management_workspace is enabled, so the workspace triple below is
# populated.
# ─────────────────────────────────────────────────────────────────────────────

module "nsg_flow_logs_hub_primary" {
  source = "../../modules/nsg-flow-logs"
  count  = var.enable_nsg_flow_logs && length(module.hub_primary.nsg_ids) > 0 ? 1 : 0

  location             = var.primary_region
  region_code          = var.primary_region_code
  environment          = "prod"
  resource_group_name  = module.hub_primary.resource_group_name
  storage_account_name = "stflowlogshub${var.primary_region_code}prod"
  nsg_ids              = module.hub_primary.nsg_ids

  # The module's log_analytics_workspace_id is the SHORT GUID, not the ARM ID
  # that platform-management's identically-named output carries. Passing the
  # ARM ID here type-checks, plans clean and yields a Traffic Analytics
  # configuration that never receives data.
  log_analytics_workspace_id          = local.management_workspace.guid
  log_analytics_workspace_resource_id = local.management_workspace.resource_id
  log_analytics_workspace_region      = local.management_workspace.location

  # Still a knowing posture reduction, but the reason has changed with TODO
  # item 2.10: the zone above now exists and is linked to this hub VNet, so
  # what blocks the endpoint is that hub-network exposes no private-endpoint
  # subnet to put it in — unlike spoke-network, which has carried pe_subnet_id
  # all along. Adding one means claiming another block of the hub address
  # space, which is a hub-topology change rather than a flow-log change, so it
  # is carried as its own follow-up (TODO item 2.11) rather than smuggled in
  # here. The storage account is already default_action = "Deny" with a
  # trusted-services bypass, so this stays defence in depth, not the only
  # control.
  enable_private_endpoint = false

  # The module's two scheduled-query alert rules notify through
  # action_group_ids; no action group is relayed to this layer, and a rule with
  # an empty action group fires into nothing.
  enable_traffic_alerts = false

  tags = local.common_tags
}

module "nsg_flow_logs_hub_dr" {
  source = "../../modules/nsg-flow-logs"
  count  = var.enable_nsg_flow_logs && length(module.hub_dr.nsg_ids) > 0 ? 1 : 0

  location             = var.dr_region
  region_code          = var.dr_region_code
  environment          = "prod"
  resource_group_name  = module.hub_dr.resource_group_name
  storage_account_name = "stflowlogshub${var.dr_region_code}prod"
  nsg_ids              = module.hub_dr.nsg_ids

  log_analytics_workspace_id          = local.management_workspace.guid
  log_analytics_workspace_resource_id = local.management_workspace.resource_id
  log_analytics_workspace_region      = local.management_workspace.location

  # Same two knowing reductions as the primary-region instance above — the
  # endpoint waits on a hub private-endpoint subnet (item 2.11), not on a zone.
  enable_private_endpoint = false
  enable_traffic_alerts   = false

  tags = local.common_tags
}
