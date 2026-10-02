resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

module "network" {
  source = "../../modules/network"

  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  name_prefix                 = var.name_prefix
  address_space               = var.vnet_address_space
  aks_subnet_address_prefixes = var.aks_subnet_address_prefixes
}

module "identity" {
  source = "../../modules/identity"

  name                = "${var.name_prefix}-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  subnet_id = module.network.aks_subnet_id
}

module "aks" {
  source = "../../modules/aks"

  depends_on = [module.identity]

  name                = var.aks_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  subnet_id   = module.network.aks_subnet_id
  identity_id = module.identity.id

  node_count   = var.node_count
  node_vm_size = var.node_vm_size

  sku_tier        = var.aks_sku_tier
  node_pool_zones = var.node_pool_zones
  pod_cidr        = var.aks_pod_cidr
  service_cidr    = var.aks_service_cidr
}
