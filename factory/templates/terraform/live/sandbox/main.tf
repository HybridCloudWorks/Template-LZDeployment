# ─────────────────────────────────────────────────────────────────────────────
# Sandbox layer — one time-boxed resource group.
#
# Copied verbatim: nothing here varies with configuration. The values that do
# arrive through terraform.auto.tfvars.
#
# The provider is not pinned to a subscription here. The sandbox layer runs
# with credentials scoped to the sandbox subscription, so binding a
# subscription ID in code would only create a second place for the two to
# disagree.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }
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
