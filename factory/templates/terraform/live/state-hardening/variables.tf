# Variable declarations for the state-hardening layer (ADR 0019, stage 2).
# This file is the contract the schema-drift check validates against; it is
# copied verbatim, never templated.

variable "state_subscription_id" {
  description = "Subscription that hosts the Terraform state storage account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.state_subscription_id))
    error_message = "state_subscription_id must be a GUID."
  }
}

variable "state_resource_group_name" {
  description = "Resource group of the state storage account (created by the bootstrap broker — never managed here)."
  type        = string
}

variable "state_storage_account_name" {
  description = "State storage account name (created by the bootstrap broker — never managed here)."
  type        = string
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

variable "hub_pe_subnet_id" {
  description = "Resource ID of the hub subnet that hosts the state private endpoint. Owned by the platform-connectivity layer — copy it from that layer's outputs after it applies. The plan fails until it is set."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("(?i)/subnets/", var.hub_pe_subnet_id))
    error_message = "hub_pe_subnet_id must be a subnet resource ID from the platform-connectivity layer (…/virtualNetworks/<vnet>/subnets/<subnet>). It is deliberately not defaulted: this layer can only run after the hub exists."
  }
}

variable "blob_private_dns_zone_id" {
  description = "Resource ID of the privatelink.blob.core.windows.net private DNS zone. Owned by the platform-connectivity layer — copy it from that layer's outputs after it applies. The plan fails until it is set."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("(?i)/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", var.blob_private_dns_zone_id))
    error_message = "blob_private_dns_zone_id must be the resource ID of the privatelink.blob.core.windows.net zone from the platform-connectivity layer."
  }
}

variable "default_tags" {
  description = "Tags applied to every resource this layer creates."
  type        = map(string)
  default     = {}
}
