variable "create_sandbox_rg" {
  description = "Whether to create the sandbox resource group"
  type        = bool
  default     = false
  nullable    = false
}

variable "resource_group_name" {
  description = "Name of the sandbox resource group"
  type        = string
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be 1-90 characters"
  }
}

variable "location" {
  description = "Azure region for the sandbox resource group"
  type        = string
  nullable    = false

  # Bound must match the azureRegion definition in
  # factory/schema/lz-config.schema.json, which is ^[a-z0-9]+$. The original
  # ^[a-z]+$ rejected every numbered region — eastus2, westus3, southeastasia's
  # numbered neighbours — so a valid wizard selection failed only at plan time.
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

  nullable = false

  validation {
    condition     = contains(["temporary", "permanent"], var.sandbox_tags.lifecycle)
    error_message = "Lifecycle must be 'temporary' or 'permanent'"
  }

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.sandbox_tags.created_date))
    error_message = "created_date must be in ISO 8601 format (YYYY-MM-DD)"
  }

  validation {
    condition     = var.sandbox_tags.expiry_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.sandbox_tags.expiry_date))
    error_message = "expiry_date must be in ISO 8601 format (YYYY-MM-DD) or null"
  }
}
