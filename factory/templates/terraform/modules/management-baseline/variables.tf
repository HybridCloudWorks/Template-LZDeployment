# Variables for Management Baseline Module

variable "org_prefix" {
  description = "Organization prefix for naming"
  type        = string
}

variable "location" {
  description = "Azure region for management resources"
  type        = string
}

variable "region_code" {
  description = "Short region code for naming (e.g., scus, neu)"
  type        = string
}

variable "log_retention_days" {
  description = "Log Analytics retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "alert_email_receivers" {
  description = "Email receivers attached to the alert action group"
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Module = "management-baseline"
    Tier   = "management"
  }
}

variable "student_resource_group_name" {
  # DEMO WIRING (TechCon workshop) — remove after the event; see the operator's
  # gitignored revert dossier. Empty string is the PRODUCT behaviour: this
  # module creates its own resource group exactly as designed. A non-empty
  # value makes it CONSUME a pre-existing resource group instead, which is what
  # lets many students share one subscription without creating groups they have
  # no permission to create.
  description = "Demo only. When set, deploy into this pre-existing resource group instead of creating one. Empty means create, which is the normal behaviour."
  type        = string
  default     = ""
}
