# Outbound internet access for the cluster.
#
# snet-aks refuses implicit outbound access, so this NAT gateway is what gives the
# nodes a stable egress address that the outside world can allow-list. The other
# three subnets do not initiate outbound traffic and are left without one.

resource "azurerm_public_ip" "aks_outbound" {
  name                = "pip-aks-outbound"
  resource_group_name = azurerm_virtual_network.this.resource_group_name
  location            = azurerm_virtual_network.this.location
  tags                = var.tags

  allocation_method = "Static"
  sku               = "Standard"

  # Non-zonal: the node pool is not pinned to a zone, and a zonal gateway serves
  # only resources in its own zone.
}

resource "azurerm_nat_gateway" "aks" {
  name                = "natgw-aks"
  resource_group_name = azurerm_virtual_network.this.resource_group_name
  location            = azurerm_virtual_network.this.location
  tags                = var.tags

  sku_name = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "aks" {
  nat_gateway_id       = azurerm_nat_gateway.aks.id
  public_ip_address_id = azurerm_public_ip.aks_outbound.id
}

# A subnet can have at most one NAT gateway, and only the cluster subnet gets one.
resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.aks.id
}
