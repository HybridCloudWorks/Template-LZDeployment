variable "workload_nonprod_subscription_id" {
  description = "Shared non-production workload subscription ID"
  type        = string
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
