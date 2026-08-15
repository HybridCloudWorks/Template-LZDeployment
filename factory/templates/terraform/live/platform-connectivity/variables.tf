# Variable declarations for the platform-connectivity layer.
# This file is the contract the schema-drift check validates against; it is
# copied verbatim, never templated. It declares the union of what both
# topologies consume — the rendered main.tf contains exactly one topology.

variable "connectivity_subscription_id" {
  description = "Subscription that hosts platform networking."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.connectivity_subscription_id))
    error_message = "connectivity_subscription_id must be a GUID."
  }
}

variable "org_prefix" {
  description = "Organization prefix used in resource names."
  type        = string
}

variable "primary_region" {
  description = "Primary Azure region."
  type        = string
}

variable "primary_region_code" {
  description = "Short code for the primary region, used in resource names."
  type        = string
}

variable "dr_region" {
  description = "DR Azure region. Empty for a single-region estate."
  type        = string
  default     = ""
}

variable "dr_region_code" {
  description = "Short code for the DR region."
  type        = string
  default     = ""
}

variable "primary_hub_address_space" {
  description = "CIDR of the primary hub network (hub VNet, or Virtual Hub prefix)."
  type        = string
}

variable "dr_hub_address_space" {
  description = "CIDR of the DR hub network. Empty emits no DR hub."
  type        = string
  default     = ""
}

variable "firewall_enabled" {
  description = "Deploy Azure Firewall in each hub."
  type        = bool
  default     = true
}

variable "azfw_tier" {
  description = "Azure Firewall tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.azfw_tier)
    error_message = "azfw_tier must be Standard or Premium."
  }
}

variable "deploy_bastion" {
  description = "Deploy Azure Bastion in each hub (hub-and-spoke only)."
  type        = bool
  default     = false
}

variable "deploy_vpn_gateway" {
  description = "Deploy a VPN gateway in each hub."
  type        = bool
  default     = false
}

variable "deploy_expressroute_gateway" {
  description = "Deploy an ExpressRoute gateway in each hub."
  type        = bool
  default     = false
}

variable "deploy_private_dns" {
  description = "Create centralized private DNS zones linked to the hubs (hub-and-spoke only)."
  type        = bool
  default     = false
}

variable "private_dns_zones" {
  description = "Private DNS zone names to create when deploy_private_dns is true."
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "Availability zones for zone-redundant hub components."
  type        = list(number)
  default     = [1, 2, 3]
}

variable "hub_and_spoke_networks_settings" {
  description = "Pass-through for the pattern module's global settings object. Defaults suffice for most estates."
  type        = any
  default     = {}
}

variable "default_tags" {
  description = "Tags applied to every resource this layer creates."
  type        = map(string)
  default     = {}
}
