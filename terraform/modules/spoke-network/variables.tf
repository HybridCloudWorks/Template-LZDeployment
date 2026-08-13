variable "spoke_name" {
  description = "Name identifier for the spoke (e.g., 'prod-app', 'nonprod-web')"
  type        = string
}

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
}

variable "spoke_address_space" {
  description = "Address space for spoke VNet (e.g., 10.1.0.0/16)"
  type        = string
}

variable "enable_hub_peering" {
  description = "Enable peering to hub VNet"
  type        = bool
  default     = true
}

variable "hub_vnet_id" {
  description = "Hub VNet resource ID"
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = "Hub VNet name"
  type        = string
  default     = ""
}

variable "hub_resource_group_name" {
  description = "Hub resource group name"
  type        = string
  default     = ""
}

variable "enable_forced_tunneling" {
  description = "Enable forced tunneling (default route) to firewall"
  type        = bool
  default     = true
}

variable "firewall_private_ip" {
  description = "Firewall private IP address for UDR next hop"
  type        = string
  default     = "10.0.1.4"
}

variable "use_remote_gateways" {
  description = "Use hub's VPN/ER gateways"
  type        = bool
  default     = false
}

variable "additional_security_rules" {
  description = "Extra NSG rules applied to the app and data subnets, above the built-in AzureLoadBalancer allow (4095) and deny-all floor (4096). Priorities must be below 4095."
  type = list(object({
    name                         = string
    priority                     = number
    direction                    = string
    access                       = string
    protocol                     = string
    source_port_range            = optional(string, "*")
    destination_port_range       = optional(string, "*")
    source_address_prefix        = optional(string)
    source_address_prefixes      = optional(list(string))
    destination_address_prefix   = optional(string)
    destination_address_prefixes = optional(list(string))
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.additional_security_rules : rule.priority >= 100 && rule.priority < 4095
    ])
    error_message = "additional_security_rules priorities must be between 100 and 4094 so the built-in AzureLoadBalancer allow and deny-all floor keep their positions."
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
