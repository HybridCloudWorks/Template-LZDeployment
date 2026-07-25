# Spoke Network Module
# Creates spoke VNet with peering to hub and default route to firewall

# Resource group for spoke
resource "azurerm_resource_group" "spoke" {
  name     = "rg-${var.spoke_name}-${var.region_code}-${var.environment}-01"
  location = var.region
  tags     = var.tags
}

# Spoke virtual network
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-${var.spoke_name}-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location
  address_space       = [var.spoke_address_space]
  tags                = var.tags
}

# Default application subnet
resource "azurerm_subnet" "app" {
  name                 = "snet-${var.spoke_name}-app-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_address_space, 2, 0)]
}

# Data subnet
resource "azurerm_subnet" "data" {
  name                 = "snet-${var.spoke_name}-data-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_address_space, 2, 1)]
}

# Private endpoint subnet
resource "azurerm_subnet" "pe" {
  name                 = "snet-${var.spoke_name}-pe-${var.region_code}-${var.environment}-01"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [cidrsubnet(var.spoke_address_space, 4, 8)]
}

# NSG for application subnet
resource "azurerm_network_security_group" "app" {
  name                = "nsg-${var.spoke_name}-app-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location
  tags                = var.tags
  
  # Default deny all inbound
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# NSG for data subnet
resource "azurerm_network_security_group" "data" {
  name                = "nsg-${var.spoke_name}-data-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location
  tags                = var.tags
  
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# NSG for private endpoint subnet (minimal rules)
resource "azurerm_network_security_group" "pe" {
  name                = "nsg-${var.spoke_name}-pe-${var.region_code}-${var.environment}-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

# UDR for application subnet - default route to firewall
resource "azurerm_route_table" "app" {
  count                         = var.enable_forced_tunneling ? 1 : 0
  name                          = "udr-${var.spoke_name}-app-${var.region_code}-${var.environment}-01"
  resource_group_name           = azurerm_resource_group.spoke.name
  location                      = azurerm_resource_group.spoke.location
  bgp_route_propagation_enabled = false
  tags                          = var.tags
  
  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "app" {
  count          = var.enable_forced_tunneling ? 1 : 0
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app[0].id
}

# UDR for data subnet
resource "azurerm_route_table" "data" {
  count                         = var.enable_forced_tunneling ? 1 : 0
  name                          = "udr-${var.spoke_name}-data-${var.region_code}-${var.environment}-01"
  resource_group_name           = azurerm_resource_group.spoke.name
  location                      = azurerm_resource_group.spoke.location
  bgp_route_propagation_enabled = false
  tags                          = var.tags
  
  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "data" {
  count          = var.enable_forced_tunneling ? 1 : 0
  subnet_id      = azurerm_subnet.data.id
  route_table_id = azurerm_route_table.data[0].id
}

# VNet peering: spoke to hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                        = var.enable_hub_peering ? 1 : 0
  name                         = "peer-${var.spoke_name}-to-hub-${var.region_code}"
  resource_group_name          = azurerm_resource_group.spoke.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateways
}

# VNet peering: hub to spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                        = var.enable_hub_peering ? 1 : 0
  name                         = "peer-hub-to-${var.spoke_name}-${var.region_code}"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}
