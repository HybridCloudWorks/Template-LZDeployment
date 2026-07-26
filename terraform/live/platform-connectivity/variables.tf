variable "connectivity_subscription_id" {
  description = "Connectivity subscription ID"
  type        = string
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
  default     = "southcentralus"
}

variable "primary_region_code" {
  description = "Primary region short code"
  type        = string
  default     = "scus"
}

variable "dr_region" {
  description = "DR Azure region"
  type        = string
  default     = "northcentralus"
}

variable "dr_region_code" {
  description = "DR region short code"
  type        = string
  default     = "ncus"
}

variable "primary_hub_address_space" {
  description = "Address space for primary hub VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_hub_address_space" {
  description = "Address space for DR hub VNet"
  type        = string
  default     = "10.10.0.0/16"
}

variable "firewall_type" {
  description = "Firewall type: azfw, palo, or fortinet"
  type        = string

  validation {
    condition     = contains(["azfw", "palo", "fortinet"], var.firewall_type)
    error_message = "Firewall type must be one of: azfw, palo, fortinet."
  }
}

variable "azfw_tier" {
  description = "Azure Firewall tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "primary_nva_trust_ip" {
  description = "Placeholder IP for primary NVA trust interface (if using Palo/Fortinet)"
  type        = string
  default     = "10.0.1.4"
}

variable "dr_nva_trust_ip" {
  description = "Placeholder IP for DR NVA trust interface (if using Palo/Fortinet)"
  type        = string
  default     = "10.10.1.4"
}

variable "deploy_bastion" {
  description = "Deploy Bastion subnet placeholders"
  type        = bool
  default     = true
}

variable "deploy_dns" {
  description = "Deploy DNS resolver subnet placeholders"
  type        = bool
  default     = true
}

variable "management_ip_ranges" {
  description = "IP ranges allowed to access management interfaces"
  type        = string
  default     = "*"
}

variable "primary_availability_zones" {
  description = "Availability zones for primary region"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "dr_availability_zones" {
  description = "Availability zones for DR region"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for hub diagnostics"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    owner       = "Platform Team"
    application = "Landing Zone Connectivity"
    environment = "prod"
    cost_center = "IT-Platform"
    managed_by  = "Terraform"
  }
}
