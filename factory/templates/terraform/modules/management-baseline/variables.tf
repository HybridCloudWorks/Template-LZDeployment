# Variables for Management Baseline Module

variable "org_prefix" {
  description = "Organization prefix for naming"
  type        = string
}

variable "location" {
  description = "Azure region for management resources"
  type        = string
}

variable "region_code" {
  description = "Short region code for naming (e.g., scus, neu)"
  type        = string
}

variable "log_retention_days" {
  description = "Log Analytics retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Module = "management-baseline"
    Tier   = "management"
  }
}
