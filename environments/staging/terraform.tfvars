location = "uksouth"

resource_group_name         = "rg-cronus-staging"
aks_name                    = "aks-cronus-staging"
name_prefix                 = "cronus-staging"
vnet_address_space          = ["10.10.0.0/16"]
aks_subnet_address_prefixes = ["10.10.0.0/24"]

node_count   = 2
node_vm_size = "Standard_D2s_v5"

aks_sku_tier     = "Standard"
node_pool_zones  = ["1", "2"]
aks_pod_cidr     = "10.245.0.0/16"
aks_service_cidr = "10.3.0.0/16"
