terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"

      # azurerm.hub targets the connectivity subscription that owns the hub
      # VNet; the hub side of the peering must be created there, not in the
      # spoke's subscription.
      configuration_aliases = [azurerm.hub]
    }
  }
}
