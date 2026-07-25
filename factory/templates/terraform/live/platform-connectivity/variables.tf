variable "connectivity_subscription_id" {
  description = "Connectivity subscription ID"
  type        = string
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
}

variable "primary_region_code" {
  description = "Primary region short code"
  type        = string
}

variable "dr_region" {
  # No default. The DR hub is only instantiated when the configuration declares
  # a DR region, and the renderer omits both this assignment and the module
  # block together — a default here would make a half-configured DR hub look
  # deployable.
  description = "DR Azure region. Empty when the landing zone is single-region."
  type        = string
  default     = ""
}

variable "dr_region_code" {
  description = "DR region short code. Empty when the landing zone is single-region."
  type        = string
  default     = ""
}

variable "primary_hub_address_space" {
  description = "Address space for primary hub VNet"
  type        = string
}

variable "dr_hub_address_space" {
  description = "Address space for DR hub VNet"
  type        = string
  default     = ""
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
  # Bound must match connectivity.firewall.azfwTier in the schema, which is an
  # enum of Standard, Premium, Basic. Basic was absent from the live layer's
  # implicit contract; it is accepted here so a wizard-selected Basic tier does
  # not fail at plan time.
  description = "Azure Firewall tier (Basic, Standard, or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.azfw_tier)
    error_message = "Azure Firewall tier must be one of: Basic, Standard, Premium."
  }
}

variable "firewall_threat_intel_mode" {
  # The hub-network module has implemented threat intelligence since
  # firewall-threat-intel.tf landed, but the live connectivity layer never
  # plumbed a variable through to it, so the module default silently governed.
  # The wizard exposes connectivity.firewall.threatIntelligenceMode; without
  # this variable that choice would render into a .tfvars entry Terraform
  # ignores. Secure default is Deny, matching the schema.
  description = "Azure Firewall threat intelligence mode (Alert, Deny, or Off)"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Alert", "Deny", "Off"], var.firewall_threat_intel_mode)
    error_message = "Threat intelligence mode must be one of: Alert, Deny, Off."
  }
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
  # Not exposed by the wizard: the schema has no key for operator source
  # ranges, so the value cannot come from lz-config.json today. The default is
  # deliberately "*" to match the live layer's behaviour rather than silently
  # tightening it, but "*" means every source address reaches management
  # interfaces. Set this per landing zone before the first apply.
  description = "IP ranges allowed to access management interfaces. '*' allows all sources."
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
  # Cross-layer input: platform-management owns the workspace, and the two
  # layers keep separate state, so this is wired by the operator (or by a
  # remote-state read added once the management layer exports it). Empty means
  # hub diagnostics are not sent anywhere.
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
