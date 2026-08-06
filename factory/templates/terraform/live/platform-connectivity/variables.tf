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
  description = "Firewall type: azfw, palo, fortinet, or none (no egress appliance in the hub)"
  type        = string

  validation {
    condition     = contains(["azfw", "palo", "fortinet", "none"], var.firewall_type)
    error_message = "Firewall type must be one of: azfw, palo, fortinet, none."
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
  # Not exposed by the wizard: the schema deliberately has no key for operator
  # source ranges (contract #4), so the value cannot come from lz-config.json.
  # No default: every landing zone must state which operator ranges may reach
  # firewall management interfaces before the first apply — the rendered
  # terraform.auto.tfvars carries a commented placeholder to uncomment, and
  # the generated plan workflow fails fast while it is unset. Wildcards are
  # rejected by the hub-network module as well.
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
  # Default false so the FIRST plan of a freshly generated repository succeeds:
  # the generated plan workflow plans every rendered layer on every PR, and an
  # ungated remote-state read of platform-management would fail red until that
  # layer's first apply (try() cannot rescue a provider read — only count
  # works). Flip to true in a PR after platform-management has been applied
  # once; the hub diagnostics then follow the central workspace automatically.
  description = "Read the central Log Analytics workspace ID from the platform-management layer's state. Enable after platform-management's first apply."
  type        = bool
  default     = false
}

variable "state_resource_group_name" {
  # Consumed only by the azurerm form of the platform-management remote-state
  # read (wire_management_workspace = true). Under the HCP Terraform backend
  # the read is addressed by organization and workspace instead, and this is
  # unused — so it must not be required.
  description = "Terraform state resource group name (azurerm backend only)"
  type        = string
  default     = ""
}

variable "state_storage_account_name" {
  description = "Terraform state storage account name (azurerm backend only)"
  type        = string
  default     = ""
}

variable "state_container_name" {
  # Must match the container backend.tf writes to. Every layer shares one
  # container and is separated by state key, so a remote-state read that
  # assumed a container per layer would find nothing and fail with an
  # unhelpful "no outputs" error.
  description = "Terraform state container name (azurerm backend only)"
  type        = string
  default     = "tfstate"
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
