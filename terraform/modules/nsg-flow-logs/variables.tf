variable "location" {
  description = "Azure region"
  type        = string
}

variable "region_code" {
  description = "Short region code (e.g., scus, ncus)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., prod, dev)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for flow log resources"
  type        = string
}

variable "storage_account_name" {
  # Null keeps the name this module has always composed —
  # stflowlogs${region_code}${environment} — so existing callers are
  # unaffected. Supply a value when more than one instance of this module must
  # exist in the same (region, environment): storage account names are
  # globally unique, so two instances sharing the composed name plan clean and
  # then collide at apply (contract 8a).
  description = "Override for the flow-log storage account name. Null composes stflowlogs<region_code><environment>. Required when a second instance shares a region and environment with an existing one."
  type        = string
  default     = null

  validation {
    # Azure storage account naming: 3–24 characters, lowercase letters and
    # digits only. Checked here rather than left to the API so a bad override
    # fails at plan instead of part-way through an apply.
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters of lowercase letters and digits only."
  }
}

variable "nsg_ids" {
  description = "Map of NSG names to NSG resource IDs to enable flow logs on"
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID (short format)"
  type        = string
}

variable "log_analytics_workspace_resource_id" {
  description = "Log Analytics workspace resource ID (full ARM format)"
  type        = string
}

variable "log_analytics_workspace_region" {
  description = "Log Analytics workspace region"
  type        = string
}

variable "flow_log_retention_days" {
  description = "Number of days to retain flow logs in storage"
  type        = number
  default     = 90
}

variable "enable_traffic_analytics" {
  description = "Enable Traffic Analytics for flow logs"
  type        = bool
  default     = true
}

variable "traffic_analytics_interval" {
  description = "Traffic Analytics processing interval in minutes (10 or 60)"
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 60], var.traffic_analytics_interval)
    error_message = "Traffic Analytics interval must be 10 or 60 minutes."
  }
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for flow logs storage account"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoint (required if enable_private_endpoint = true)"
  type        = string
  default     = ""
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs for blob storage private endpoint"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access flow logs storage account"
  type        = list(string)
  default     = []
}

variable "allowed_ip_cidrs" {
  description = "Public IPv4 CIDR ranges allowed through the flow-logs storage account firewall. Entries that fail to parse are dropped (fail closed)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.allowed_ip_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")
    ])
    error_message = "Each entry in allowed_ip_cidrs must be a valid IPv4 CIDR (e.g. 203.0.113.0/24)."
  }
}

variable "enable_traffic_alerts" {
  description = "Enable alerts for unusual traffic patterns"
  type        = bool
  default     = true
}

variable "action_group_ids" {
  description = "Action Group IDs for traffic alerts"
  type        = list(string)
  default     = []
}

variable "high_traffic_threshold_gb" {
  description = "Threshold in GB for high traffic alert"
  type        = number
  default     = 100
}

variable "denied_traffic_threshold" {
  description = "Threshold for denied traffic flows to trigger alert"
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
