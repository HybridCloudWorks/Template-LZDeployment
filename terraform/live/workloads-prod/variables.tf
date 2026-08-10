variable "workload_prod_subscription_id" {
  description = "Production workload subscription ID"
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Connectivity subscription ID (owns the hub side of each peering)"
  type        = string
}

variable "state_resource_group_name" {
  description = "Terraform state resource group name"
  type        = string
}

variable "state_storage_account_name" {
  description = "Terraform state storage account name"
  type        = string
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
  default     = "southcentralus"
}

variable "primary_region_code" {
  description = "Primary region code"
  type        = string
  default     = "scus"
}

variable "dr_region" {
  description = "DR Azure region"
  type        = string
  default     = "northcentralus"
}

variable "dr_region_code" {
  description = "DR region code"
  type        = string
  default     = "ncus"
}

variable "primary_spoke_address_space" {
  description = "Address space for primary production spoke"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_spoke_address_space" {
  description = "Address space for DR production spoke"
  type        = string
  default     = "10.11.0.0/16"
}

variable "default_tags" {
  description = "Default tags"
  type        = map(string)
  default = {
    owner       = "Workload Team"
    application = "Production Workloads"
    environment = "prod"
    cost_center = "IT-Applications"
    managed_by  = "Terraform"
  }
}

variable "enable_nsg_flow_logs" {
  # Default false so a plan succeeds before the spokes exist (decision 0009,
  # the wire_management_workspace shape): the module reads
  # NetworkWatcher_${location} in NetworkWatcherRG through the default
  # provider, and that resource group is only created when the subscription's
  # first VNet appears. A provider read cannot be rescued by try() — only
  # count. Flip in a PR after the spokes' first apply and after
  # platform-connectivity's wire_management_workspace is enabled.
  description = "Collect NSG flow logs for the production spokes' app, data and private-endpoint NSGs. Enable after the spokes' first apply."
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
