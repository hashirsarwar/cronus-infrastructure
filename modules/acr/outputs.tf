output "id" {
  description = "Resource id of the registry, for role assignments scoped to it."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Name of the registry."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Login server that images are pushed to and pulled from, for example acrcronusnonprod.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}
