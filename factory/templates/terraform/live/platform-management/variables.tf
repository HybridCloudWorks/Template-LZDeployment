variable "management_subscription_id" {
  description = "Management subscription ID"
  type        = string
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
