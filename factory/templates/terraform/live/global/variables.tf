# Variable declarations for the global (ALZ core) layer.
# This file is the contract the schema-drift check validates against; it is
# copied verbatim, never templated.

variable "architecture_name" {
  description = "ALZ library architecture to deploy. Must exist in the pinned library reference."
  type        = string
  default     = "alz"
}

variable "root_parent_management_group_id" {
  description = "Parent for the ALZ hierarchy. Empty deploys under the tenant root group."
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary Azure region for policy-managed deployments."
  type        = string
}

variable "management_subscription_id" {
  description = "Management subscription (also the provider's default subscription)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.management_subscription_id))
    error_message = "management_subscription_id must be a GUID."
  }
}

variable "connectivity_subscription_id" {
  description = "Connectivity subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "identity_subscription_id" {
  description = "Identity subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "workload_prod_subscription_id" {
  description = "Production workload subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "workload_nonprod_subscription_id" {
  description = "Non-production workload subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "sandbox_subscription_id" {
  description = "Sandbox subscription. Empty places nothing."
  type        = string
  default     = ""
}

# Management-group IDs for subscription placement. Defaults match the id set
# the pinned `alz` architecture defines; override only alongside a custom
# architecture definition.

variable "management_management_group_id" {
  description = "Management-group ID that receives the management subscription."
  type        = string
  default     = "management"
}

variable "connectivity_management_group_id" {
  description = "Management-group ID that receives the connectivity subscription."
  type        = string
  default     = "connectivity"
}

variable "identity_management_group_id" {
  description = "Management-group ID that receives the identity subscription."
  type        = string
  default     = "identity"
}

variable "landing_zones_management_group_id" {
  description = "Management-group ID that receives workload subscriptions."
  type        = string
  default     = "landingzones"
}

variable "sandbox_management_group_id" {
  description = "Management-group ID that receives the sandbox subscription."
  type        = string
  default     = "sandboxes"
}

# Remote-state read of the platform-management layer.

variable "state_resource_group_name" {
  description = "Resource group of the state storage account."
  type        = string
}

variable "state_storage_account_name" {
  description = "State storage account."
  type        = string
}

variable "state_container_name" {
  description = "State container."
  type        = string
}
