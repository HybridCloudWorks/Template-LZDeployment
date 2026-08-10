variable "root_mg_id" {
  description = "Root management group resource ID"
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

variable "sandbox_mg_id" {
  description = "Sandbox management group ID"
  type        = string
}

variable "allowed_locations" {
  description = "List of allowed Azure regions"
  type        = list(string)
  default     = ["southcentralus", "northcentralus"]
}

variable "landingzones_mg_id" {
  # Separate from platform_mg_id on purpose: the public-network-access
  # assignment must NOT reach the platform management group, which holds the
  # Terraform state storage account. That account cannot be
  # private-endpoint-only during bootstrap — the client's own machine creates
  # the estate from it (decision 0004).
  description = "Landing Zones management group ID. Scope for workload-facing policy assignments."
  type        = string
  default     = ""
}

variable "assign_public_network_access_policy" {
  # Renders from connectivity.privateEndpoints.denyPublicNetworkAccessPolicy
  # (TODO item 2.14). Default false, like every posture flag decision 0009
  # introduced: assigning a policy across a client's landing zones is a change
  # they should make in a PR, not one a default makes for them.
  description = "Assign the initiative auditing (or denying) public network access on PaaS data services, scoped to the Landing Zones management group."
  type        = bool
  default     = false
}

variable "public_network_access_effect" {
  # Audit, not Deny, and deliberately so: this estate creates storage accounts
  # that keep public network access enabled behind network rules — the
  # flow-log accounts and the state account during setup. A Deny here would
  # fail a generated repository's first apply on the platform's own resources.
  # Tighten to Deny in a PR once those are behind private endpoints.
  description = "Effect for the public-network-access initiative: Audit, Deny, or Disabled."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.public_network_access_effect)
    error_message = "public_network_access_effect must be one of: Audit, Deny, Disabled."
  }
}
