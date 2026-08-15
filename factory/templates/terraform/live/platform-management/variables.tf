# Variable declarations for the platform-management layer.
# This file is the contract the schema-drift check validates against; it is
# copied verbatim, never templated.

variable "management_subscription_id" {
  description = "Subscription that hosts the management baseline."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.management_subscription_id))
    error_message = "management_subscription_id must be a GUID."
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

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 90
}

variable "default_tags" {
  description = "Tags applied to every resource this layer creates."
  type        = map(string)
  default     = {}
}
