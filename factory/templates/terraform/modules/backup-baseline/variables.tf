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
