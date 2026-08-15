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

variable "deploy_private_dns_zones" {
  # Renamed from deploy_blob_private_dns_zone (TODO item 2.12) now that it
  # gates a list rather than one zone. Default false, like every other gate
  # decision 0009 introduced: this is the switch that turns the workload
  # layers' flow-log private endpoints ON (they derive
  # enable_private_endpoint from whether the blob zone exists), and a posture
  # change belongs in a PR rather than in a default. Flip it, apply this
  # layer, then apply the workload layers.
  #
  # Separate from deploy_dns: that one creates DNS *resolver subnet
  # placeholders* inside the hub VNets and creates no zone at all.
  description = "Create the private DNS zones in var.private_dns_zones in the connectivity subscription and link them to both hub VNets. Enables the workload layers' flow-log private endpoints when the blob zone is among them."
  type        = bool
  default     = false
}

variable "private_dns_zones" {
  # Empty means the blob zone alone — the one zone item 2.10 shipped and the
  # only one anything in this repository consumes. It does NOT mean "the CAF
  # default set for the services you enabled": the schema and the wizard hint
  # promised that, nothing implemented it, and creating a set of zones the
  # client never asked for is not a good way to make the promise true. The
  # wording was corrected instead (TODO item 2.12).
  description = "Private DNS zone names to create and link to both hubs. Empty means privatelink.blob.core.windows.net alone."
  type        = list(string)
  default     = []

  # Loosest of the three bounds (contract #7): the wizard and the schema may be
  # stricter than this, never the reverse. Azure allows up to 34 labels and 253
  # characters; a leading or trailing dot, an empty label or an uppercase
  # letter is rejected here rather than at apply.
  validation {
    condition = alltrue([
      for z in var.private_dns_zones :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", z)) && length(z) <= 253
    ])
    error_message = "Each private DNS zone must be a lowercase dotted name of at least two labels, no leading/trailing dot or hyphen, 253 characters or fewer."
  }

  validation {
    condition     = length(var.private_dns_zones) == length(distinct(var.private_dns_zones))
    error_message = "private_dns_zones must not contain duplicates — two entries of the same name are one zone and would collide on the link name."
  }
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

# Consumed only under the azurerm backend: the remote-state reads take the
# organization/workspaces branch under HCP Terraform, and the tfvars emit these
# three only when computed.backendIsAzurerm. The corpus ships ONE variables.tf
# for both backends, so under an HCP render they are declared and unreferenced.
# Making the declarations conditional would turn this file into a template —
# a structural change to how the corpus renders variables, and not one to make
# to silence a lint rule. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "state_resource_group_name" {
  # Consumed only by the azurerm form of the platform-management remote-state
  # read (wire_management_workspace = true). Under the HCP Terraform backend
  # the read is addressed by organization and workspace instead, and this is
  # unused — so it must not be required.
  description = "Terraform state resource group name (azurerm backend only)"
  type        = string
  default     = ""
}

# Consumed only under the azurerm backend: the remote-state reads take the
# organization/workspaces branch under HCP Terraform, and the tfvars emit these
# three only when computed.backendIsAzurerm. The corpus ships ONE variables.tf
# for both backends, so under an HCP render they are declared and unreferenced.
# Making the declarations conditional would turn this file into a template —
# a structural change to how the corpus renders variables, and not one to make
# to silence a lint rule. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "state_storage_account_name" {
  description = "Terraform state storage account name (azurerm backend only)"
  type        = string
  default     = ""
}

# Consumed only under the azurerm backend: the remote-state reads take the
# organization/workspaces branch under HCP Terraform, and the tfvars emit these
# three only when computed.backendIsAzurerm. The corpus ships ONE variables.tf
# for both backends, so under an HCP render they are declared and unreferenced.
# Making the declarations conditional would turn this file into a template —
# a structural change to how the corpus renders variables, and not one to make
# to silence a lint rule. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "state_container_name" {
  # Must match the container backend.tf writes to. Every layer shares one
  # container and is separated by state key, so a remote-state read that
  # assumed a container per layer would find nothing and fail with an
  # unhelpful "no outputs" error.
  description = "Terraform state container name (azurerm backend only)"
  type        = string
  default     = "tfstate"
}

variable "enable_nsg_flow_logs" {
  # Same shape and reasoning as the workload layers' flag (decision 0009).
  # Default false so the FIRST plan of a freshly generated repository succeeds:
  # the module reads NetworkWatcher_${location} in NetworkWatcherRG through the
  # default provider, and Azure creates that resource group only once the
  # subscription's first VNet exists. A provider read cannot be rescued by
  # try() — only count. Flip in a PR after the hubs' first apply and after
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

variable "primary_private_endpoint_subnet_prefix" {
  # Operator-supplied because no cidrsubnet() index is free under both the
  # azfw and palo/fortinet hub layouts — see the comment on
  # azurerm_subnet.private_endpoints in modules/hub-network (TODO item 2.11).
  description = "CIDR for the primary hub's private-endpoint subnet, from your own address plan. Null leaves hub private endpoints unavailable."
  type        = string
  default     = null
  nullable    = true
}

variable "dr_private_endpoint_subnet_prefix" {
  description = "CIDR for the DR hub's private-endpoint subnet, from your own address plan. Null leaves hub private endpoints unavailable."
  type        = string
  default     = null
  nullable    = true
}

variable "private_endpoint_allowed_source_prefixes" {
  # Operator-supplied like the two prefix variables above, and for a related
  # reason: these are the spoke CIDRs hosting flow-log storage (decision 0012),
  # and this layer does not know them — the workload layers read connectivity's
  # state, never the reverse, and inverting that read would be a cycle. Empty
  # means the hub private-endpoint NSGs associate without custom rules (Azure
  # defaults govern); once set, the hubs allow 443 from these ranges only.
  # One list serves both hubs: the sources are an estate-wide answer, not a
  # per-region one.
  description = "Spoke CIDR ranges allowed to reach hub private endpoints on 443 (the flow-log-hosting spokes). Empty leaves the private-endpoint NSGs without custom rules. Wildcard sources are rejected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.private_endpoint_allowed_source_prefixes : !contains(["*", "0.0.0.0/0"], r)
    ])
    error_message = "private_endpoint_allowed_source_prefixes must not include '*' or '0.0.0.0/0' - supply the explicit spoke CIDRs."
  }
}

variable "enable_private_endpoints" {
  # Same wizard answer the workload layers consume (item 2.14). The hub's
  # endpoints honour it too, so unticking the box turns off every private
  # endpoint in the estate rather than only the spokes'.
  description = "Create private endpoints for this layer's PaaS resources. Requires a hub private-endpoint subnet prefix and the blob private DNS zone as well."
  type        = bool
  default     = true
}

variable "flow_log_storage_replication_type" {
  # TODO item 2.8. Passed to every nsg-flow-logs call in this layer. The
  # default matches the module's and changes no existing plan; a
  # residency-constrained estate sets LRS or ZRS so no flow log is replicated
  # to the Azure paired region.
  description = "Replication for this layer's flow-log storage accounts. LRS and ZRS keep data in one region."
  type        = string
  default     = "RAGZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.flow_log_storage_replication_type)
    error_message = "flow_log_storage_replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}
