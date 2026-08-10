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

variable "assign_public_network_access_policy" {
  # Renders from connectivity.privateEndpoints.denyPublicNetworkAccessPolicy
  # (TODO item 2.14), which the wizard has collected since the factory shipped
  # with nothing consuming it.
  description = "Assign the initiative auditing public network access on PaaS data services across the Landing Zones management group."
  type        = bool
  default     = false
}

variable "public_network_access_effect" {
  # See the module variable of the same name for why the default is Audit and
  # not Deny — the estate's own storage accounts would fail a Deny.
  description = "Effect for the public-network-access initiative: Audit, Deny, or Disabled."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.public_network_access_effect)
    error_message = "public_network_access_effect must be one of: Audit, Deny, Disabled."
  }
}
