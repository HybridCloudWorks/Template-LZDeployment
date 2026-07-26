# Platform Connectivity - Dual-Region Hubs
# Deploy after global layer

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  backend "azurerm" {
    # Configuration provided via backend.hcl
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.connectivity_subscription_id
}

locals {
  common_tags = merge(var.default_tags, {
    layer = "platform-connectivity"
  })
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
  nva_trust_ip_placeholder   = var.primary_nva_trust_ip
  deploy_bastion_placeholder = var.deploy_bastion
  deploy_dns_placeholder     = var.deploy_dns
  management_ip_ranges       = var.management_ip_ranges
  availability_zones         = var.primary_availability_zones
  log_analytics_workspace_id = var.log_analytics_workspace_id
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
  nva_trust_ip_placeholder   = var.dr_nva_trust_ip
  deploy_bastion_placeholder = var.deploy_bastion
  deploy_dns_placeholder     = var.deploy_dns
  management_ip_ranges       = var.management_ip_ranges
  availability_zones         = var.dr_availability_zones
  log_analytics_workspace_id = var.log_analytics_workspace_id
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
