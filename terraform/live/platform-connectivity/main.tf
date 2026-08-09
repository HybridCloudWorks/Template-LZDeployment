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

  # Knowing posture reduction (decision 0009, constraint 4): the module's
  # private endpoint needs a privatelink.blob.core.windows.net zone and no such
  # zone exists in either tree. The storage account is already
  # default_action = "Deny" with a trusted-services bypass, so the private
  # endpoint is defence in depth rather than the only control. TODO item 2.10
  # owns re-enabling it.
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

  # Same two knowing reductions as the primary-region instance above.
  enable_private_endpoint = false
  enable_traffic_alerts   = false

  tags = local.common_tags
}
