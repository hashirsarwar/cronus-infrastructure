variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "identity_id" {
  type = string
}

variable "node_count" {
  type = number
}

variable "node_vm_size" {
  type = string
}

variable "sku_tier" {
  type = string
}

variable "node_pool_zones" {
  type = list(string)
}

variable "pod_cidr" {
  type = string
}

variable "service_cidr" {
  type = string
}
