variable "root_mg_id" {
  description = "Root management group ID"
  type        = string
}

variable "root_management_group_id" {
  description = "Root management group ID (full resource ID format)"
  type        = string
}

variable "location" {
  description = "Azure region for policy assignment managed identity"
  type        = string
  default     = "southcentralus"
}

variable "platform_mg_id" {
  description = "Platform management group ID"
  type        = string
}

variable "landingzones_mg_id" {
  description = "Landing Zones management group ID"
  type        = string
}

variable "sandbox_mg_id" {
  description = "Sandbox management group ID"
  type        = string
}

variable "allowed_locations" {
  description = "List of allowed Azure regions"
  type        = list(string)
  default     = ["southcentralus", "northcentralus"]
}
