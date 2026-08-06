# Workload Production Spokes
# Deploy after platform connectivity

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.workload_prod_subscription_id
}

# The hub side of each VNet peering must be created in the connectivity
# subscription that owns the hub VNet, not in the workload subscription.
provider "azurerm" {
  alias           = "hub"
  subscription_id = var.connectivity_subscription_id
  features {}
}

# Data source for hub outputs
data "terraform_remote_state" "connectivity" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = "platform-connectivity"
    key                  = "terraform.tfstate"
    # State storage disables shared keys; without AAD auth this read 403s.
    use_azuread_auth = true
  }
}

locals {
  primary_hub = data.terraform_remote_state.connectivity.outputs.primary_hub_details
  dr_hub      = data.terraform_remote_state.connectivity.outputs.dr_hub_details

  common_tags = merge(var.default_tags, {
    layer = "workload-prod"
  })
}

# Production spoke in primary region
module "spoke_prod_primary" {
  source = "../../modules/spoke-network"

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  spoke_name              = "prod-app"
  region                  = var.primary_region
  region_code             = var.primary_region_code
  environment             = "prod"
  spoke_address_space     = var.primary_spoke_address_space
  enable_hub_peering      = true
  hub_vnet_id             = local.primary_hub.vnet_id
  hub_vnet_name           = local.primary_hub.vnet_name
  hub_resource_group_name = local.primary_hub.resource_group_name
  enable_forced_tunneling = true
  firewall_private_ip     = local.primary_hub.firewall_private_ip
  use_remote_gateways     = false
  tags                    = local.common_tags
}

# Production spoke in DR region
module "spoke_prod_dr" {
  source = "../../modules/spoke-network"

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  spoke_name              = "prod-app"
  region                  = var.dr_region
  region_code             = var.dr_region_code
  environment             = "prod"
  spoke_address_space     = var.dr_spoke_address_space
  enable_hub_peering      = true
  hub_vnet_id             = local.dr_hub.vnet_id
  hub_vnet_name           = local.dr_hub.vnet_name
  hub_resource_group_name = local.dr_hub.resource_group_name
  enable_forced_tunneling = true
  firewall_private_ip     = local.dr_hub.firewall_private_ip
  use_remote_gateways     = false
  tags                    = local.common_tags
}
