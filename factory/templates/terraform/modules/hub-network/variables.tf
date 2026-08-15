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
  description = "Placeholder IP for NVA trust interface (used until NVA deployed). Defaults to the first usable host of the trust subnet derived from hub_address_space."
  type        = string
  default     = null
  nullable    = true
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
  description = "CIDR ranges allowed to reach firewall management interfaces. Must be explicit ranges; wildcard sources are rejected."
  type        = list(string)

  validation {
    condition = length(var.management_ip_ranges) > 0 && alltrue([
      for r in var.management_ip_ranges : !contains(["*", "0.0.0.0/0"], r)
    ])
    error_message = "management_ip_ranges must contain at least one CIDR and must not include '*' or '0.0.0.0/0'."
  }
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
    state = string # Alert, Deny, or Off
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
  description = "Log Analytics workspace resource ID for diagnostics. Empty string disables diagnostic settings and threat-intel alerts."
  type        = string
  default     = ""
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


variable "private_endpoint_subnet_prefix" {
  # No default index: see the long comment on azurerm_subnet.private_endpoints
  # in main.tf — no cidrsubnet() index is free under both the azfw and the
  # palo/fortinet layouts, so a derived default would collide with one of them
  # (TODO item 2.11). Null means no subnet, which is what this module did
  # before the variable existed.
  description = "CIDR for the hub's private-endpoint subnet, supplied from your own address plan. Null creates no subnet and leaves hub private endpoints unavailable."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.private_endpoint_subnet_prefix == null || can(cidrhost(var.private_endpoint_subnet_prefix, 0))
    error_message = "private_endpoint_subnet_prefix must be valid CIDR notation, or null."
  }
}

variable "private_endpoint_allowed_source_prefixes" {
  # Consumed by the private-endpoint subnet's NSG (TODO item 2.16, decision
  # 0012). Operator-supplied for the same reason private_endpoint_subnet_prefix
  # is: the ranges are spoke CIDRs, which live in the workload layers and are
  # not derivable here. Empty means the NSG carries NO custom rules — the
  # association exists but Azure's default rules govern — because an allowlist
  # nobody populated would deny everything and silently break the flow-log
  # storage endpoints. Wildcards are rejected like management_ip_ranges;
  # a wildcard allowlist is no allowlist.
  description = "CIDR ranges allowed to reach the hub's private endpoints on 443 (the flow-log-hosting spoke ranges). Empty associates the NSG without custom rules. Wildcard sources are rejected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.private_endpoint_allowed_source_prefixes : !contains(["*", "0.0.0.0/0"], r)
    ])
    error_message = "private_endpoint_allowed_source_prefixes must not include '*' or '0.0.0.0/0' - supply the explicit spoke CIDRs."
  }
}
