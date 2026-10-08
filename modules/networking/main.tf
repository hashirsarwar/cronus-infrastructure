# Fixed subnet names keep consumers and delegations consistent across environments.
# Implicit outbound access is disabled; AKS egress uses the NAT gateway in egress.tf.

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                            = "snet-aks"
  resource_group_name             = azurerm_virtual_network.this.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = var.subnet_address_prefixes.aks
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "aks_apiserver" {
  name                            = "snet-aks-apiserver"
  resource_group_name             = azurerm_virtual_network.this.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = var.subnet_address_prefixes.aks_apiserver
  default_outbound_access_enabled = false

  # Dedicate this subnet to the API server; at least /28 is needed for its reserved addresses and scaling.
  delegation {
    name = "aks-apiserver"

    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                            = "snet-postgres"
  resource_group_name             = azurerm_virtual_network.this.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = var.subnet_address_prefixes.postgres
  default_outbound_access_enabled = false

  # A flexible server with VNet integration takes ownership of this subnet.
  delegation {
    name = "postgres"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  # Keep the Storage endpoint Azure adds for PostgreSQL WAL traffic.
  # Removing it can break the server; declaring it also avoids perpetual drift.
  service_endpoint {
    service = "Microsoft.Storage"
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                            = "snet-private-endpoints"
  resource_group_name             = azurerm_virtual_network.this.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = var.subnet_address_prefixes.private_endpoints
  default_outbound_access_enabled = false

  # Azure does not apply a network security group to private endpoints while
  # network policies are disabled on the subnet, which would leave
  # nsg-private-endpoints with nothing to filter.
  private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
}
