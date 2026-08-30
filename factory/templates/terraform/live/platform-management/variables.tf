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

# The wizard's -1 ("no cap") is not emitted into tfvars at all, so an uncapped
# workspace leaves this null and the module applies no quota. A positive value
# caps daily ingestion — which caps the bill, and can also drop security
# telemetry once the cap is hit.
variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB for the Log Analytics workspace. Null means uncapped."
  type        = number
  default     = null

  validation {
    condition     = var.log_daily_quota_gb == null || var.log_daily_quota_gb > 0
    error_message = "log_daily_quota_gb must be a positive number, or null for uncapped. Use null rather than -1: -1 is the wizard's spelling of uncapped, not the module's."
  }
}

variable "default_tags" {
  description = "Tags applied to every resource this layer creates."
  type        = map(string)
  default     = {}
}
