location = "uksouth"

resource_group_name         = "rg-cronus-nonprod"
aks_name                    = "aks-cronus-nonprod"
name_prefix                 = "cronus-nonprod"
vnet_address_space          = ["10.0.0.0/16"]
aks_subnet_address_prefixes = ["10.0.0.0/24"]

node_count   = 1
node_vm_size = "Standard_D4s_v6"

aks_sku_tier     = "Free"
node_pool_zones  = []
aks_pod_cidr     = "10.244.0.0/16"
aks_service_cidr = "10.2.0.0/16"
