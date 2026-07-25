variable "org_prefix" {
  # Bound must match organization.companyShortName in
  # factory/schema/lz-config.schema.json. The renderer's drift check compares
  # this regex against the schema pattern and fails the build on a mismatch,
  # because a value the wizard accepts but this rejects fails only at plan time.
  #
  # 10 characters is the ceiling because storage account names are limited to 24
  # lowercase alphanumeric characters in total, and the prefix is only one
  # segment of the generated name.
  description = "Organization prefix for resource naming (2-10 lowercase alphanumeric)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.org_prefix))
    error_message = "Organization prefix must be 2-10 lowercase alphanumeric characters."
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
