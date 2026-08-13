variable "workload_nonprod_subscription_id" {
  description = "Shared non-production workload subscription ID"
  type        = string
}

variable "connectivity_subscription_id" {
  # Feeds the azurerm.hub provider alias: the hub side of each VNet peering is
  # created in the connectivity subscription that owns the hub VNet. Empty when
  # the landing zone has no platform hub — the template then aliases azurerm.hub
  # to the workload provider and creates no peering.
  description = "Connectivity subscription ID that owns the hub VNet (hub-and-spoke landing zones only)"
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
variable "state_resource_group_name" {
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
  description = "Terraform state container name (azurerm backend only)"
  type        = string
  default     = "tfstate"
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
}

variable "primary_region_code" {
  description = "Primary region code"
  type        = string
}

variable "dr_region" {
  description = "DR Azure region; empty for single-region configurations"
  type        = string
  default     = ""
}

variable "dr_region_code" {
  description = "DR region code; empty for single-region configurations"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "dev_primary_spoke_address_space" {
  description = "Dev primary spoke CIDR"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "dev_dr_spoke_address_space" {
  description = "Dev DR spoke CIDR"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "test_primary_spoke_address_space" {
  description = "Test primary spoke CIDR"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "test_dr_spoke_address_space" {
  description = "Test DR spoke CIDR"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "uat_primary_spoke_address_space" {
  description = "UAT primary spoke CIDR"
  type        = string
  default     = ""
}

# Declared for every non-production environment, consumed only for the ones
# this client selected: the spoke modules in main.tf render per selected
# environment, so a configuration choosing dev alone leaves the test and uat
# pairs unreferenced. Same shape as the state_* variables above — one static
# variables.tf serving several render shapes — and the same reasoning applies:
# making the declarations conditional is a structural change to the corpus,
# not a lint fix. TODO item 2.15.
# tflint-ignore: terraform_unused_declarations
variable "uat_dr_spoke_address_space" {
  description = "UAT DR spoke CIDR"
  type        = string
  default     = ""
}

variable "default_tags" {
  description = "Default tags"
  type        = map(string)
  default     = {}
}

variable "enable_nsg_flow_logs" {
  # Default false so a plan succeeds before the spokes exist (decision 0009,
  # the wire_management_workspace shape): the module reads
  # NetworkWatcher_${location} in NetworkWatcherRG through the default
  # provider, and that resource group is only created when the subscription's
  # first VNet appears. A provider read cannot be rescued by try() — only
  # count. Flip in a PR after the spokes' first apply and after
  # platform-connectivity's wire_management_workspace is enabled.
  description = "Collect NSG flow logs for the non-production spokes' app, data and private-endpoint NSGs. Enable after the spokes' first apply."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  # Deliberately unbounded here: the schema constrains
  # security.nsgFlowLogs.retentionDays to 1-365 and contract #7 only permits
  # bounds to widen left to right (wizard subset of schema subset of
  # Terraform). Adding a validation block narrower than 1-365 would invert it.
  description = "Days NSG flow logs are retained in the flow-logs storage account"
  type        = number
  default     = 90
}

variable "enable_traffic_analytics" {
  # Turning this off removes the Traffic Analytics processing and workspace
  # ingestion meters — roughly nine tenths of the flow-log bill — and leaves
  # raw logs in blob storage that nothing queries.
  description = "Process NSG flow logs through Traffic Analytics into the central Log Analytics workspace"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  # Renders from connectivity.privateEndpoints.enabled (TODO item 2.14).
  # Default true matches the schema default and the wizard's pre-checked box,
  # so this changes nothing for anyone who left it alone — it gives the client
  # who UNTICKED it the effect they asked for, which they previously did not
  # get. It ANDs with the connectivity layer's private DNS zone: no zone means
  # no endpoint regardless, because an endpoint without a zone resolves to
  # nothing (contract 9).
  description = "Create private endpoints for this layer's PaaS resources. Requires the connectivity layer's private DNS zone to exist as well."
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

variable "student_resource_group_name" {
  # DEMO WIRING (TechCon workshop) — remove after the event; see the operator's
  # gitignored revert dossier. Rendered from github.ownerName, which for the
  # workshop equals the student's pre-created resource group. Empty is the
  # PRODUCT behaviour: every module creates its own resource groups as designed.
  description = "Demo only. When set, this layer's modules deploy into this pre-existing resource group instead of creating their own."
  type        = string
  default     = ""
}
