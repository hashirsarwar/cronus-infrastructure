variable "location" {
  type    = string
  default = "uksouth"
}

variable "resource_group_name" {
  type = string
}

variable "aks_name" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "vnet_address_space" {
  type = list(string)
}

variable "aks_subnet_address_prefixes" {
  type = list(string)
}

variable "aks_sku_tier" {
  type = string
}

variable "node_pool_zones" {
  type = list(string)
}

variable "aks_pod_cidr" {
  type = string
}

variable "aks_service_cidr" {
  type = string
}
