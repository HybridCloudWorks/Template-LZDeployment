variable "org_prefix" {
  description = "Organization prefix for naming (2-4 lowercase letters)"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.org_prefix))
    error_message = "Organization prefix must be 2-4 lowercase letters."
  }
}

variable "management_subscription_id" {
  description = "Management subscription ID"
  type        = string
}

variable "identity_subscription_id" {
  description = "Identity subscription ID"
  type        = string
  default     = ""
}

variable "connectivity_subscription_id" {
  description = "Connectivity subscription ID"
  type        = string
}

variable "workload_prod_subscription_id" {
  description = "Production workload subscription ID"
  type        = string
}

variable "workload_nonprod_subscription_id" {
  description = "Non-production workload subscription ID"
  type        = string
}

variable "sandbox_subscription_id" {
  description = "Sandbox subscription ID"
  type        = string
}

variable "allowed_locations" {
  description = "List of allowed Azure regions"
  type        = list(string)
  default     = ["southcentralus", "northcentralus"]
}
