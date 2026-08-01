# Microsoft Defender for Cloud Baseline
# Enables Defender plans for the subscription the provider targets
# (single-subscription module contract; instantiate once per subscription)

variable "defender_tier" {
  description = "Defender pricing tier applied to every enabled plan (Standard or Free)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Free"], var.defender_tier)
    error_message = "Defender tier must be Standard or Free."
  }
}

variable "security_contact_email" {
  description = "Email address for security alerts and notifications"
  type        = string
}

variable "security_contact_phone" {
  description = "Phone number for security contact (optional)"
  type        = string
  default     = ""
}

variable "enable_defender_for_servers" {
  description = "Enable Defender for Servers"
  type        = bool
  default     = true
}

variable "enable_defender_for_app_services" {
  description = "Enable Defender for App Services"
  type        = bool
  default     = true
}

variable "enable_defender_for_storage" {
  description = "Enable Defender for Storage"
  type        = bool
  default     = true
}

variable "enable_defender_for_sql" {
  description = "Enable Defender for SQL"
  type        = bool
  default     = true
}

variable "enable_defender_for_containers" {
  description = "Enable Defender for Containers (includes AKS)"
  type        = bool
  default     = true
}

variable "enable_defender_for_key_vault" {
  description = "Enable Defender for Key Vault"
  type        = bool
  default     = true
}

variable "enable_defender_for_resource_manager" {
  description = "Enable Defender for Azure Resource Manager"
  type        = bool
  default     = true
}

variable "enable_defender_for_dns" {
  description = "Enable Defender for DNS"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Defender data export"
  type        = string
}

variable "default_tags" {
  description = "Default tags to apply to resources"
  type        = map(string)
  default     = {}
}
