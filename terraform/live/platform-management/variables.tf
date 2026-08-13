variable "management_subscription_id" {
  description = "Management subscription ID"
  type        = string
}

variable "org_prefix" {
  # Bound must match organization.companyShortName in
  # factory/schema/lz-config.schema.json (same contract as the global layer).
  description = "Organization prefix for resource naming (2-10 lowercase alphanumeric)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.org_prefix))
    error_message = "Organization prefix must be 2-10 lowercase alphanumeric characters."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention period in days"
  type        = number
  default     = 90

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "alert_email_receivers" {
  description = "Email receivers attached to the platform alert action group"
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}

variable "sandbox_subscription_id" {
  description = "Sandbox subscription ID for cleanup automation"
  type        = string
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
  default     = "southcentralus"
}

variable "primary_region_code" {
  description = "Primary region short code"
  type        = string
  default     = "scus"
}

variable "dr_region" {
  description = "DR Azure region"
  type        = string
  default     = "northcentralus"
}

variable "dr_region_code" {
  description = "DR region short code"
  type        = string
  default     = "ncus"
}

variable "default_tags" {
  description = "Default tags"
  type        = map(string)
  default = {
    owner       = "Platform Team"
    application = "Landing Zone Management"
    environment = "prod"
    cost_center = "IT-Platform"
    managed_by  = "Terraform"
  }
}

variable "student_resource_group_name" {
  # DEMO WIRING (TechCon workshop) — remove after the event; see the operator's
  # gitignored revert dossier. Rendered from github.ownerName, which for the
  # workshop equals the student's pre-created resource group. Empty is the
  # PRODUCT behaviour: every module creates its own resource groups as designed.
  description = "Demo only. When set, this layer's modules deploy into this pre-existing resource group instead of creating their own."
  type        = string
  default     = ""
}
