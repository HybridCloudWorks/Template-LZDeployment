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

variable "hub_address_space" {
  description = "Address space for hub VNet (e.g., 10.0.0.0/16)"
  type        = string
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
  
  validation {
    condition     = contains(["Standard", "Premium"], var.azfw_tier)
    error_message = "Azure Firewall tier must be Standard or Premium."
  }
}

variable "nva_trust_ip_placeholder" {
  description = "Placeholder IP for NVA trust interface (used until NVA deployed)"
  type        = string
  default     = "10.0.1.4"
}

variable "deploy_bastion_placeholder" {
  description = "Create Bastion subnet placeholder"
  type        = bool
  default     = true
}

variable "deploy_dns_placeholder" {
  description = "Create DNS resolver subnet placeholders"
  type        = bool
  default     = true
}

variable "management_ip_ranges" {
  description = "IP ranges allowed to access firewall management (CIDR or '*')"
  type        = string
  default     = "*"
}

variable "availability_zones" {
  description = "Availability zones for zonal resources"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}

# Threat Intelligence Variables (Phase 2 - Task 5.3)

variable "enable_firewall_threat_intel" {
  description = "Enable Azure Firewall Threat Intelligence"
  type        = bool
  default     = false
}

variable "firewall_threat_intel_mode" {
  description = "Threat Intelligence mode: Off, Alert, or Deny"
  type        = string
  default     = "Alert"
  
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_threat_intel_mode)
    error_message = "Threat Intelligence mode must be: Off, Alert, or Deny."
  }
}

variable "firewall_threat_intel_allowlist_ips" {
  description = "IP addresses to bypass Threat Intelligence (trusted IPs)"
  type        = list(string)
  default     = []
}

variable "firewall_threat_intel_allowlist_fqdns" {
  description = "FQDNs to bypass Threat Intelligence (trusted domains)"
  type        = list(string)
  default     = []
}

variable "firewall_dns_servers" {
  description = "Custom DNS servers for firewall DNS proxy (empty = Azure DNS)"
  type        = list(string)
  default     = []
}

variable "firewall_idps_mode" {
  description = "IDPS mode for Premium SKU: Off, Alert, or Deny"
  type        = string
  default     = "Alert"
  
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_idps_mode)
    error_message = "IDPS mode must be: Off, Alert, or Deny."
  }
}

variable "firewall_idps_signature_overrides" {
  description = "IDPS signature overrides for custom threat handling"
  type = list(object({
    id    = string
    state = string  # Alert, Deny, or Off
  }))
  default = []
}

variable "firewall_idps_traffic_bypass" {
  description = "Traffic bypass rules for IDPS"
  type = list(object({
    name                  = string
    protocol              = string
    description           = string
    destination_addresses = list(string)
    destination_ports     = list(string)
    source_addresses      = list(string)
    source_ip_groups      = list(string)
  }))
  default = []
}

variable "firewall_enable_tls_inspection" {
  description = "Enable TLS inspection (Premium SKU only)"
  type        = bool
  default     = false
}

variable "firewall_tls_certificate_key_vault_secret_id" {
  description = "Key Vault secret ID for TLS inspection certificate (Premium SKU)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 90
}

variable "enable_threat_intel_alerts" {
  description = "Enable alerts for threat intelligence hits"
  type        = bool
  default     = true
}

variable "security_action_group_ids" {
  description = "Action Group IDs for security alerts"
  type        = list(string)
  default     = []
}

