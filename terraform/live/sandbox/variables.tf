variable "create_sandbox_rg" {
  description = "Whether to create the sandbox resource group"
  type        = bool
  default     = false
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the sandbox resource group"
  type        = string
  default     = "rg-sandbox-dev-eastus"
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be 1-90 characters"
  }
}

variable "location" {
  # Bound must match the azureRegion definition in the schema (^[a-z0-9]+$)
  # and the factory-corpus copy of this layer. The previous ^[a-z]+$ rejected
  # every numbered region — eastus2, westus3 — so a perfectly valid wizard
  # selection failed only at plan time.
  description = "Azure region for the sandbox resource group"
  type        = string
  default     = "eastus"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Location must be a valid Azure region short name, e.g. southcentralus or eastus2."
  }
}

variable "sandbox_tags" {
  description = <<-EOT
    Tags for the sandbox resource group.

    Required fields:
    - environment: Resource environment (e.g., 'sandbox', 'dev', 'test')
    - lifecycle: Resource lifecycle ('temporary' or 'permanent')
    - created_date: Creation date in ISO 8601 format (YYYY-MM-DD)

    Optional fields:
    - expiry_date: Expiration date in ISO 8601 format (YYYY-MM-DD)
    - owner: Owner or team name
  EOT

  type = object({
    environment  = string
    lifecycle    = string
    created_date = string
    expiry_date  = optional(string)
    owner        = optional(string)
  })

  default = {
    environment  = "sandbox"
    lifecycle    = "temporary"
    created_date = "2026-06-30"
    expiry_date  = "2026-07-30"
    owner        = "platform-team"
  }

  nullable = false
}
