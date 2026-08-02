terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

module "sandbox" {
  source = "../../modules/sandbox"

  create_sandbox_rg   = var.create_sandbox_rg
  resource_group_name = var.resource_group_name
  location            = var.location
  sandbox_tags        = var.sandbox_tags
}
