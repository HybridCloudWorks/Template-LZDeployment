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
