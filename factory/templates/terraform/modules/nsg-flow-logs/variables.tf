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

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
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
