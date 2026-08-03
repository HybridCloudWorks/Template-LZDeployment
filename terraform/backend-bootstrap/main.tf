# Terraform Backend Bootstrap
# This creates the storage account for remote state management
# Run this once locally before using remote state

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = var.management_subscription_id

  # The state storage account disables shared keys, and the provider manages
  # its containers over the data plane — without this it falls back to
  # key-based auth and gets KeyBasedAuthenticationNotPermitted.
  storage_use_azuread = true
}

# Random suffix for globally unique storage account name
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Resource group for state backend
resource "azurerm_resource_group" "state" {
  name     = "rg-tfstate-${var.primary_region_code}-prod-01"
  location = var.primary_region
  tags = merge(var.default_tags, {
    purpose = "Terraform State Backend"
  })
}

# Storage account for state files
resource "azurerm_storage_account" "state" {
  name                     = "st${var.org_prefix}tfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "RAGZRS"
  account_kind             = "StorageV2"

  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # State access is via Azure AD (OIDC) only; shared keys stay off so a leaked
  # key can never read state.
  shared_access_key_enabled = false

  # Security - CRITICAL: Public access disabled by default (Finding 1.2 - CVSS 8.2)
  public_network_access_enabled = var.allow_public_access_during_setup

  # Lifecycle precondition: block public access unless a private endpoint is
  # also being provisioned (public access is a temporary setup bridge, not a
  # steady state).
  lifecycle {
    precondition {
      condition     = !var.allow_public_access_during_setup || var.enable_private_endpoint
      error_message = <<-EOT
        SECURITY WARNING (Finding 1.2 - CVSS 8.2):
        Public network access is ENABLED on Terraform state storage.
        This exposes sensitive infrastructure data to the internet.
        
        REMEDIATION:
        1. Set allow_public_access_during_setup = false
        2. Deploy private endpoint (enable_private_endpoint = true)
        3. Configure management_vnet_id and management_subnet_id
        
        Only enable public access temporarily during initial setup.
      EOT
    }
  }

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  # Deny by default even while public network access is temporarily enabled;
  # only the explicitly allowed CIDRs (parsed fail-closed below) get through.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = local.state_ip_rules
  }

  tags = merge(var.default_tags, {
    purpose = "Terraform State Storage"
  })
}

locals {
  # Azure storage ip_rules accept public IPv4 addresses or CIDR ranges, with
  # /32 written as a bare address. The parser fails closed: an entry that does
  # not parse as an IPv4 CIDR is dropped, narrowing access instead of
  # widening it, and an empty result leaves default_action = "Deny" in force.
  state_ip_rules = [
    for c in var.allowed_ip_cidrs :
    (endswith(c, "/32") ? split("/", c)[0] : c)
    if can(cidrhost(c, 0)) && !strcontains(c, ":")
  ]
}

# Private DNS Zone for Blob Storage
resource "azurerm_private_dns_zone" "blob" {
  count               = var.enable_private_endpoint ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.state.name

  tags = var.default_tags
}

# Link Private DNS Zone to Management VNet
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.enable_private_endpoint && var.management_vnet_id != "" ? 1 : 0
  name                  = "link-${var.org_prefix}-tfstate-to-mgmt-vnet"
  resource_group_name   = azurerm_resource_group.state.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = var.management_vnet_id
  registration_enabled  = false

  tags = var.default_tags
}

# Private Endpoint for State Storage
resource "azurerm_private_endpoint" "state_blob" {
  count               = var.enable_private_endpoint && var.management_subnet_id != "" ? 1 : 0
  name                = "pe-${azurerm_storage_account.state.name}-blob"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  subnet_id           = var.management_subnet_id

  private_service_connection {
    name                           = "psc-tfstate-blob"
    private_connection_resource_id = azurerm_storage_account.state.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }

  tags = merge(var.default_tags, {
    purpose = "Private connectivity to Terraform state storage"
  })
}

# State containers for each layer
resource "azurerm_storage_container" "state_containers" {
  for_each = toset([
    "global-mgmt-groups",
    "global-policies",
    "platform-connectivity",
    "platform-management",
    "platform-identity",
    "workloads-prod",
    "workloads-nonprod",
    "sandbox-isolation"
  ])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Log Analytics workspace for diagnostics
resource "azurerm_log_analytics_workspace" "state" {
  name                = "log-tfstate-${var.primary_region_code}-prod-01"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.default_tags
}

# Diagnostic settings for state storage. The StorageRead/Write/Delete log
# categories exist on the blob service sub-resource, not on the storage
# account itself, so the setting targets .../blobServices/default.
resource "azurerm_monitor_diagnostic_setting" "state" {
  name                       = "diag-state-storage"
  target_resource_id         = "${azurerm_storage_account.state.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.state.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
