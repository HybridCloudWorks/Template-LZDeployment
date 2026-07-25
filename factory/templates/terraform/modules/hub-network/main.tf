# Hub Network Module
# Dual-region hub with firewall (Azure FW, Palo Alto, or Fortinet)

locals {
  # Firewall subnet sizing based on choice
  fw_subnet_sizes = {
    azfw     = { main = "/26", mgmt = null, trust = null, untrust = null }
    palo     = { main = null, mgmt = "/28", trust = "/26", untrust = "/26" }
    fortinet = { main = null, mgmt = "/28", trust = "/26", untrust = "/26" }
  }
  
  fw_config = local.fw_subnet_sizes[var.firewall_type]
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
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 3)]
}

# Bastion subnet
resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion_placeholder ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 4)]
}

# DNS resolver inbound subnet
resource "azurerm_subnet" "dns_inbound" {
  count                = var.deploy_dns_placeholder ? 1 : 0
  name                 = "snet-dns-inbound-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 5)]
  
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
  address_prefixes     = [cidrsubnet(var.hub_address_space, 4, 6)]
  
  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# NSGs for all subnets
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
    source_address_prefix      = var.management_ip_ranges
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "fw_mgmt" {
  count                     = var.firewall_type != "azfw" ? 1 : 0
  subnet_id                 = azurerm_subnet.fw_mgmt[0].id
  network_security_group_id = azurerm_network_security_group.fw_mgmt[0].id
}

# NSG for Gateway subnet (minimal rules)
resource "azurerm_network_security_group" "gateway" {
  name                = "nsg-gateway-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  tags                = var.tags
  
  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.gateway.id
}

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

# Azure Firewall
resource "azurerm_firewall" "hub" {
  count               = var.firewall_type == "azfw" ? 1 : 0
  name                = "azfw-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.azfw_tier
  zones               = var.availability_zones
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
    length(azurerm_firewall.hub) > 0 ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : var.nva_trust_ip_placeholder
  ) : var.nva_trust_ip_placeholder
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

# Log Analytics workspace for firewall logs
resource "azurerm_log_analytics_workspace" "hub" {
  name                = "log-hub-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Diagnostic settings for Azure Firewall
resource "azurerm_monitor_diagnostic_setting" "azfw" {
  count                      = var.firewall_type == "azfw" ? 1 : 0
  name                       = "diag-azfw"
  target_resource_id         = azurerm_firewall.hub[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hub.id
  
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
