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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}
