output "vnet_id" {
  description = "Resource id of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Address space of the virtual network."
  value       = azurerm_virtual_network.this.address_space
}

output "aks_subnet_id" {
  description = "Resource id of snet-aks, for the Kubernetes cluster."
  value       = azurerm_subnet.aks.id
}

output "aks_apiserver_subnet_id" {
  description = "Resource id of the subnet the AKS API server is projected into. Dedicated to that purpose, so nothing else may be placed in it."
  value       = azurerm_subnet.aks_apiserver.id
}

output "postgres_subnet_id" {
  description = "Resource id of snet-postgres, for PostgreSQL Flexible Server."
  value       = azurerm_subnet.postgres.id
}

output "private_endpoints_subnet_id" {
  description = "Resource id of snet-private-endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "nat_gateway_id" {
  description = "Resource id of the NAT gateway that provides egress for snet-aks."
  value       = azurerm_nat_gateway.aks.id
}

output "nat_gateway_public_ip_id" {
  description = "Resource id of the public IP behind the NAT gateway."
  value       = azurerm_public_ip.aks_outbound.id
}

output "nat_gateway_public_ip_address" {
  description = "The outbound address the cluster appears as on the internet. Give this to anything that allow-lists the cluster."
  value       = azurerm_public_ip.aks_outbound.ip_address
}

output "aks_nsg_id" {
  description = "Resource id of nsg-aks."
  value       = azurerm_network_security_group.aks.id
}

output "postgres_nsg_id" {
  description = "Resource id of nsg-postgres."
  value       = azurerm_network_security_group.postgres.id
}

output "private_endpoints_nsg_id" {
  description = "Resource id of nsg-private-endpoints."
  value       = azurerm_network_security_group.private_endpoints.id
}
