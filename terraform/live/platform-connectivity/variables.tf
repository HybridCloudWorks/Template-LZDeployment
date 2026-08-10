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
  description = "Firewall type: azfw, palo, or fortinet. A landing zone always deploys at least one firewall."
  type        = string

  validation {
    condition     = contains(["azfw", "palo", "fortinet"], var.firewall_type)
    error_message = "Firewall type must be one of: azfw, palo, fortinet. A landing zone always deploys at least one firewall."
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
  # Cross-layer input: platform-management owns the workspace, and the two
  # layers keep separate state. Leave this empty and flip
  # wire_management_workspace instead — the count-gated remote-state read then
  # supplies the ID. An explicitly supplied value here takes precedence over
  # the read. Empty with the gate off means hub diagnostics are not sent
  # anywhere.
  description = "Log Analytics workspace resource ID for hub diagnostics. Overrides the wire_management_workspace remote-state read when set."
  type        = string
  default     = ""
}

variable "wire_management_workspace" {
  # Mirrors the corpus connectivity layer (decision 0003). Default false so a
  # plan succeeds before platform-management has ever been applied: an ungated
  # remote-state read of that layer fails red until its first apply, and try()
  # cannot rescue a provider read — only count works. Flip to true in a PR
  # after platform-management has been applied once; hub diagnostics then
  # follow the central workspace automatically, and the workspace triple the
  # NSG flow-log wiring needs becomes available to the workload layers.
  description = "Read the central Log Analytics workspace from the platform-management layer's state. Enable after platform-management's first apply."
  type        = bool
  default     = false
}

variable "state_resource_group_name" {
  # Consumed only by the platform-management remote-state read above, so it
  # must not be required — the gate is off by default and the layer otherwise
  # has no use for it.
  description = "Terraform state resource group name (consumed by the wire_management_workspace read)"
  type        = string
  default     = ""
}

variable "state_storage_account_name" {
  description = "Terraform state storage account name (consumed by the wire_management_workspace read)"
  type        = string
  default     = ""
}

variable "enable_nsg_flow_logs" {
  # Same shape and reasoning as the workload layers' flag (decision 0009).
  # Default false so a plan succeeds before the hubs exist: the module reads
  # NetworkWatcher_${location} in NetworkWatcherRG through the default
  # provider, and that resource group is only created when the subscription's
  # first VNet appears. A provider read cannot be rescued by try() — only
  # count. Flip in a PR after the hubs' first apply and after
  # wire_management_workspace is enabled. Only has an effect on an NVA hub:
  # fw_mgmt is the sole hub NSG and hub-network creates it for palo/fortinet
  # only.
  description = "Collect NSG flow logs for the hubs' firewall-management NSGs. Enable after the hubs' first apply."
  type        = bool
  default     = false
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
