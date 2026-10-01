variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "address_space" {
  type = list(string)
}

variable "aks_subnet_address_prefixes" {
  type = list(string)
}
