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

variable "state_resource_group_name" {
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

variable "dev_primary_spoke_address_space" {
  description = "Dev primary spoke CIDR"
  type        = string
  default     = ""
}

variable "dev_dr_spoke_address_space" {
  description = "Dev DR spoke CIDR"
  type        = string
  default     = ""
}

variable "test_primary_spoke_address_space" {
  description = "Test primary spoke CIDR"
  type        = string
  default     = ""
}

variable "test_dr_spoke_address_space" {
  description = "Test DR spoke CIDR"
  type        = string
  default     = ""
}

variable "uat_primary_spoke_address_space" {
  description = "UAT primary spoke CIDR"
  type        = string
  default     = ""
}

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
