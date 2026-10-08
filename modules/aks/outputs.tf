output "id" {
  description = "Resource id of the cluster, for role assignments scoped to it."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Name of the cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer of the cluster, which a federated identity credential has to name as its issuer."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Entra ID object id of the kubelet identity, read back from the cluster. Role assignments for pulling images or reading other resources are made against this."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "node_resource_group" {
  description = "Resource group AKS created for the nodes, disks and load balancers. Separate from the environment's own resource group, and managed by AKS."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "fqdn" {
  description = "The API server's address as Azure reports it. Public and reachable only from the authorized IP ranges on a public cluster; on a private one it is the name that resolves inside the linked private DNS zone and nowhere else."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "private_fqdn" {
  description = "API server address inside the virtual network, as reported by AKS. With API server VNet integration the nodes reach the API server through its internal load balancer address in the API server subnet directly, without DNS, so this is informational rather than what clients dial. Null on a public cluster."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "current_kubernetes_version" {
  description = "Kubernetes version the cluster is actually running, which is the patch AKS chose for the requested minor."
  value       = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "gateway_api_ingress_profile" {
  description = "Ingress profile Azure reports for the cluster after the Gateway API settings were applied. This is the read-back, not the request: it is what confirms the cluster ended up with the managed Gateway API installation and the Application Routing Istio implementation."
  value       = azapi_update_resource.gateway_api.output.properties.ingressProfile
}
