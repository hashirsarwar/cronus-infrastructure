resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dns_prefix = var.name
  sku_tier   = var.sku_tier

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.subnet_id
    zones          = var.node_pool_zones
  }

  identity {
    type = "UserAssigned"

    identity_ids = [
      var.identity_id
    ]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"

    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = cidrhost(var.service_cidr, 10)

    load_balancer_sku = "standard"
  }

  node_provisioning_profile {
    mode = "Manual"
  }
}
