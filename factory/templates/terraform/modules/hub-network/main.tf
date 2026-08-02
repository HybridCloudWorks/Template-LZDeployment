# Hub Network Module
# Dual-region hub with firewall (Azure FW, Palo Alto, or Fortinet)

# Subnet plan (for a /16 hub address space):
#   - Firewall blocks occupy the low /18s:
#       AzureFirewallSubnet  cidrsubnet(space, 2, 0)  e.g. 10.0.0.0/18   (azfw only)
#       snet-fw-mgmt         cidrsubnet(space, 4, 0)  e.g. 10.0.0.0/20   (palo/fortinet only)
#       snet-fw-trust        cidrsubnet(space, 2, 1)  e.g. 10.0.64.0/18  (palo/fortinet only)
#       snet-fw-untrust      cidrsubnet(space, 2, 2)  e.g. 10.0.128.0/18 (palo/fortinet only)
#   - Shared subnets come from the high-index /20s (indexes 12-15), which sit
#     entirely inside cidrsubnet(space, 2, 3) and are therefore disjoint from
#     every firewall block above:
#       GatewaySubnet        cidrsubnet(space, 4, 12) e.g. 10.0.192.0/20
#       AzureBastionSubnet   cidrsubnet(space, 4, 13) e.g. 10.0.208.0/20
#       snet-dns-inbound     cidrsubnet(space, 4, 14) e.g. 10.0.224.0/20
#       snet-dns-outbound    cidrsubnet(space, 4, 15) e.g. 10.0.240.0/20
#   The azfw and fw-mgmt subnets share index 0 but are mutually exclusive by
#   firewall_type, so no deployed pair of subnets overlaps.

locals {
  # NVA trust interface IP: first usable host (offset 4 - Azure reserves the
  # first three usable addresses) in the trust subnet, unless the caller
  # supplies an explicit address.
  nva_trust_ip = coalesce(
    var.nva_trust_ip_placeholder,
    cidrhost(cidrsubnet(var.hub_address_space, 2, 1), 4)
  )
}

# Resource group for hub
resource "azurerm_resource_group" "hub" {
  name     = "rg-connectivity-${var.region_code}-${var.environment}-01"
  location = var.region
  tags     = var.tags
}

# Hub virtual network
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  address_space       = [var.hub_address_space]
  tags                = var.tags
}

# Azure Firewall subnet (only for azfw)
resource "azurerm_subnet" "azfw" {
  count                = var.firewall_type == "azfw" ? 1 : 0
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 0)]
}

# Firewall Management subnet (for Palo/Fortinet)
resource "azurerm_subnet" "fw_mgmt" {
  count                = var.firewall_type != "azfw" ? 1 : 0
  name                 = "snet-fw-mgmt-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 0)]
}

# Firewall Trust (internal) subnet (for Palo/Fortinet)
resource "azurerm_subnet" "fw_trust" {
  count                = var.firewall_type != "azfw" ? 1 : 0
  name                 = "snet-fw-trust-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 1)]
}

# Firewall Untrust (external) subnet (for Palo/Fortinet)
resource "azurerm_subnet" "fw_untrust" {
  count                = var.firewall_type != "azfw" ? 1 : 0
  name                 = "snet-fw-untrust-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 2, 2)]
}

# Gateway subnet
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 12)]
}

# Bastion subnet
resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion_placeholder ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 13)]
}

# DNS resolver inbound subnet
resource "azurerm_subnet" "dns_inbound" {
  count                = var.deploy_dns_placeholder ? 1 : 0
  name                 = "snet-dns-inbound-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 14)]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# DNS resolver outbound subnet
resource "azurerm_subnet" "dns_outbound" {
  count                = var.deploy_dns_placeholder ? 1 : 0
  name                 = "snet-dns-outbound-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 15)]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# NSG for the NVA management subnet
resource "azurerm_network_security_group" "fw_mgmt" {
  count               = var.firewall_type != "azfw" ? 1 : 0
  name                = "nsg-fw-mgmt-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  tags                = var.tags

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.management_ip_ranges
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "fw_mgmt" {
  count                     = var.firewall_type != "azfw" ? 1 : 0
  subnet_id                 = azurerm_subnet.fw_mgmt[0].id
  network_security_group_id = azurerm_network_security_group.fw_mgmt[0].id
}

# GatewaySubnet deliberately has no NSG: Azure does not support NSG
# associations on GatewaySubnet. Traffic inspection for gateway-transiting
# flows is handled by the hub firewall and spoke UDRs instead.

# Public IP for Azure Firewall
resource "azurerm_public_ip" "azfw" {
  count               = var.firewall_type == "azfw" ? 1 : 0
  name                = "pip-azfw-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.availability_zones
  tags                = var.tags
}

# Azure Firewall. This is the single firewall resource for the hub; when
# threat intelligence is enabled it is attached to the firewall policy defined
# in firewall-threat-intel.tf rather than being duplicated.
resource "azurerm_firewall" "hub" {
  count               = var.firewall_type == "azfw" ? 1 : 0
  name                = "azfw-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.azfw_tier
  zones               = var.availability_zones
  firewall_policy_id  = var.enable_firewall_threat_intel ? azurerm_firewall_policy.hub[0].id : null
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = azurerm_subnet.azfw[0].id
    public_ip_address_id = azurerm_public_ip.azfw[0].id
  }
}

# Placeholder outputs for NVA (Palo/Fortinet) - will be populated when NVA deployed
# These are used by spoke UDRs
locals {
  firewall_private_ip = var.firewall_type == "azfw" ? (
    length(azurerm_firewall.hub) > 0 ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : local.nva_trust_ip
  ) : local.nva_trust_ip
}

# Route table for spoke default route to firewall
resource "azurerm_route_table" "to_firewall" {
  name                = "udr-to-firewall-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  tags                = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.firewall_private_ip
  }
}

# Diagnostic settings for Azure Firewall. Skipped when no workspace is wired
# in, and superseded by the threat-intelligence diagnostic setting (which
# carries the same categories plus the threat-intel ones) when that is enabled.
resource "azurerm_monitor_diagnostic_setting" "azfw" {
  count                      = var.firewall_type == "azfw" && !var.enable_firewall_threat_intel && var.log_analytics_workspace_id != "" ? 1 : 0
  name                       = "diag-azfw"
  target_resource_id         = azurerm_firewall.hub[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_log {
    category = "AzureFirewallDnsProxy"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
