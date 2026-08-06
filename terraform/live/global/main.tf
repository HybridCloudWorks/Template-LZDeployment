# Global Infrastructure - Management Groups and Policies
# Deploy this first

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
  subscription_id = var.management_subscription_id
}

# Management Groups
module "management_groups" {
  source = "../../modules/management-groups"

  org_prefix                       = var.org_prefix
  identity_subscription_id         = var.identity_subscription_id
  connectivity_subscription_id     = var.connectivity_subscription_id
  management_subscription_id       = var.management_subscription_id
  workload_prod_subscription_id    = var.workload_prod_subscription_id
  workload_nonprod_subscription_id = var.workload_nonprod_subscription_id
  sandbox_subscription_id          = var.sandbox_subscription_id
}

# Policy Baseline
module "policy_baseline" {
  source = "../../modules/policy-baseline"

  root_mg_id         = module.management_groups.root_mg_id
  platform_mg_id     = module.management_groups.platform_mg_id
  landingzones_mg_id = module.management_groups.landingzones_mg_id
  sandbox_mg_id      = module.management_groups.sandbox_mg_id
  allowed_locations  = var.allowed_locations

  depends_on = [module.management_groups]
}
