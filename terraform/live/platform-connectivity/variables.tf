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
  # Bound matches connectivity.firewall.azfwTier in the schema (contract #7:
  # wizard ⊆ schema ⊆ terraform). Basic is deliberately NOT accepted: Azure
  # Firewall Basic mandates a dedicated AzureFirewallManagementSubnet (/26)
  # plus a management public IP that the hub-network module's
  # azurerm_firewall.hub does not provision, and Basic supports threat-intel
  # alert-only while this layer defaults to Deny. Accepting Basic here would
  # let a plan succeed for a firewall that can never deploy.
  description = "Azure Firewall tier (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.azfw_tier)
    error_message = "Azure Firewall tier must be one of: Standard, Premium."
  }
}

variable "firewall_threat_intel_mode" {
  # The hub-network module has implemented threat intelligence since
  # firewall-threat-intel.tf landed, but this layer never plumbed a variable
  # through to it, so the module default silently governed. The wizard exposes
  # connectivity.firewall.threatIntelligenceMode; without this variable that
  # choice would render into a .tfvars entry Terraform ignores. Secure default
  # is Deny, matching the schema.
  description = "Azure Firewall threat intelligence mode (Alert, Deny, or Off)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Alert", "Deny", "Off"], var.firewall_threat_intel_mode)
    error_message = "Threat intelligence mode must be one of: Alert, Deny, Off."
  }
}

variable "primary_nva_trust_ip" {
  description = "Placeholder IP for primary NVA trust interface (if using Palo/Fortinet). Null derives the first usable host of the trust subnet."
  type        = string
  default     = null
  nullable    = true
}

variable "dr_nva_trust_ip" {
  description = "Placeholder IP for DR NVA trust interface (if using Palo/Fortinet). Null derives the first usable host of the trust subnet."
  type        = string
  default     = null
  nullable    = true
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
  # No default: every landing zone must state which operator ranges may reach
  # firewall management interfaces. Wildcards are rejected by the hub-network
  # module as well.
  description = "CIDR ranges allowed to access management interfaces. Wildcard sources are rejected."
  type        = list(string)

  validation {
    condition = length(var.management_ip_ranges) > 0 && alltrue([
      for r in var.management_ip_ranges : !contains(["*", "0.0.0.0/0"], r)
    ])
    error_message = "management_ip_ranges must contain at least one CIDR and must not include '*' or '0.0.0.0/0'."
  }
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
