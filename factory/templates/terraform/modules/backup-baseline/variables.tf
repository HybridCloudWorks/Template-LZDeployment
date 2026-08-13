variable "region" {
  description = "Azure region"
  type        = string
}

variable "region_code" {
  description = "Short region code (e.g., scus, ncus)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "storage_redundancy" {
  description = "Storage redundancy for Recovery Services Vault (GeoRedundant, LocallyRedundant, ZoneRedundant)"
  type        = string
  default     = "GeoRedundant"

  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ZoneRedundant"], var.storage_redundancy)
    error_message = "Must be GeoRedundant, LocallyRedundant, or ZoneRedundant."
  }
}

variable "backup_vault_redundancy" {
  description = "Redundancy for Backup Vault (GeoRedundant, LocallyRedundant, ZoneRedundant)"
  type        = string
  default     = "GeoRedundant"

  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ZoneRedundant"], var.backup_vault_redundancy)
    error_message = "Must be GeoRedundant, LocallyRedundant, or ZoneRedundant."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}

variable "student_resource_group_name" {
  # DEMO WIRING (TechCon workshop) — remove after the event; see the operator's
  # gitignored revert dossier. Empty string is the PRODUCT behaviour: this
  # module creates its own resource group exactly as designed. A non-empty
  # value makes it CONSUME a pre-existing resource group instead, which is what
  # lets many students share one subscription without creating groups they have
  # no permission to create.
  description = "Demo only. When set, deploy into this pre-existing resource group instead of creating one. Empty means create, which is the normal behaviour."
  type        = string
  default     = ""
}
