location = "uksouth"

resource_group_name         = "rg-cronus-prod"
aks_name                    = "aks-cronus-prod"
name_prefix                 = "cronus-prod"
vnet_address_space          = ["10.20.0.0/16"]
aks_subnet_address_prefixes = ["10.20.0.0/24"]

node_count   = 3
node_vm_size = "Standard_D4s_v6"

aks_sku_tier     = "Standard"
node_pool_zones  = ["1", "3"]
aks_pod_cidr     = "10.246.0.0/16"
aks_service_cidr = "10.4.0.0/16"
