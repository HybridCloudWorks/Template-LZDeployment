variable "workload_prod_subscription_id" {
  description = "Production workload subscription ID"
  type        = string
}

variable "state_resource_group_name" {
  # Consumed only by the azurerm remote-state read of the connectivity layer.
  # Under the HCP Terraform backend the remote state is addressed by
  # organization and workspace instead, and the renderer emits that form — so
  # this must not be a required variable, or every HCP landing zone would stall
  # apply waiting for a value it has no use for.
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

variable "primary_region" {
  description = "Primary Azure region"
  type        = string
}

variable "primary_region_code" {
  description = "Primary region code"
  type        = string
}

variable "dr_region" {
  description = "DR Azure region. Empty when the landing zone is single-region."
  type        = string
  default     = ""
}

variable "dr_region_code" {
  description = "DR region code. Empty when the landing zone is single-region."
  type        = string
  default     = ""
}

variable "primary_spoke_address_space" {
  description = "Address space for primary production spoke"
  type        = string
}

variable "dr_spoke_address_space" {
  description = "Address space for DR production spoke"
  type        = string
  default     = ""
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
