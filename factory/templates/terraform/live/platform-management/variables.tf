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
  # Bound deliberately wider than the schema's 30-730
  # (observability.logAnalytics.retentionDays): contract #7 orders
  # wizard ⊂ schema ⊂ terraform, so Terraform must accept everything the
  # schema does.
  description = "Log Analytics retention period in days"
  type        = number
  default     = 90

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "alert_email_receivers" {
  # Composed by the renderer from observability.alerting.actionGroupEmails
  # (decision record 0003): notification enrollment must be an explicit act,
  # so no other contact list in the configuration ever feeds this. Empty
  # means the action group renders but alerts route nowhere.
  description = "Email receivers attached to the platform alert action group"
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}

variable "sandbox_subscription_id" {
  # Defaulted rather than required. A sandbox subscription is optional in the
  # schema, and the sandbox-cleanup automation is omitted entirely when none is
  # configured. Leaving this required would stall apply on a landing zone that
  # deliberately has no sandbox.
  description = "Sandbox subscription ID for cleanup automation. Empty when no sandbox subscription exists."
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
}

variable "primary_region_code" {
  description = "Primary region short code"
  type        = string
}

variable "dr_region" {
  description = "DR Azure region. Empty when the landing zone is single-region."
  type        = string
  default     = ""
}

variable "dr_region_code" {
  description = "DR region short code. Empty when the landing zone is single-region."
  type        = string
  default     = ""
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
