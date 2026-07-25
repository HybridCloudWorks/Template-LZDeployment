variable "org_prefix" {
  description = "Organization prefix for naming"
  type        = string
}

variable "identity_subscription_id" {
  description = "Subscription ID for Identity"
  type        = string
  default     = ""
}

variable "connectivity_subscription_id" {
  description = "Subscription ID for Connectivity"
  type        = string
  default     = ""
}

variable "management_subscription_id" {
  description = "Subscription ID for Management"
  type        = string
  default     = ""
}

variable "workload_prod_subscription_id" {
  description = "Subscription ID for Production Workloads"
  type        = string
  default     = ""
}

variable "workload_nonprod_subscription_id" {
  description = "Subscription ID for Non-Production Workloads"
  type        = string
  default     = ""
}

variable "sandbox_subscription_id" {
  description = "Subscription ID for Sandbox"
  type        = string
  default     = ""
}
