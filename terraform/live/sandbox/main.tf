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
  # Stated 5.0 default (decision 0006): the provider registers no resource
  # providers — the broker registers the required namespaces at bootstrap.
  resource_provider_registrations = "none"
}

module "sandbox" {
  source = "../../modules/sandbox"

  create_sandbox_rg   = var.create_sandbox_rg
  resource_group_name = var.resource_group_name
  location            = var.location
  sandbox_tags        = var.sandbox_tags
}
