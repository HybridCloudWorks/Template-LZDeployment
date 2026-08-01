variable "management_subscription_id" {
  description = "Subscription ID for the Management subscription where state will be stored"
  type        = string
}

variable "org_prefix" {
  description = "Organization prefix for resource naming (e.g., 'hcw')"
  type        = string
  default     = "hcw"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.org_prefix))
    error_message = "Organization prefix must be 2-4 lowercase letters."
  }
}

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
  default     = "southcentralus"
}

variable "primary_region_code" {
  description = "Short code for primary region"
  type        = string
  default     = "scus"
}

variable "allow_public_access_during_setup" {
  description = "Allow public network access during initial setup (disable after private endpoint configured)"
  type        = bool
  default     = false # SECURITY: Changed to false per Phase 1 remediation (Finding 1.2)
}

variable "management_vnet_id" {
  description = "VNet ID for private endpoint (required when public access disabled)"
  type        = string
  default     = ""
}

variable "management_subnet_id" {
  description = "Subnet ID for private endpoint (required when public access disabled)"
  type        = string
  default     = ""
}

variable "allowed_ip_cidrs" {
  description = "Public IPv4 CIDR ranges allowed through the state storage account firewall while public network access is enabled (e.g. operator egress ranges). Entries that fail to parse are dropped (fail closed)."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.allowed_ip_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")
    ])
    error_message = "Each entry in allowed_ip_cidrs must be a valid IPv4 CIDR (e.g. 203.0.113.0/24)."
  }
}

variable "enable_private_endpoint" {
  description = "Deploy private endpoint for state storage (recommended for production)"
  type        = bool
  default     = true
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    owner       = "Platform Team"
    application = "Landing Zone Infrastructure"
    environment = "prod"
    cost_center = "IT-Platform"
    managed_by  = "Terraform"
  }
}
