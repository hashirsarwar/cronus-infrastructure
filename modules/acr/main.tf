resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  sku = var.sku

  # Nobody authenticates with a registry password. The cluster and CI both use
  # Entra ID, so there is no shared credential to rotate, scope or leak.
  admin_enabled = false

  # Repository-scoped permissions. Legacy registry-wide permissions stay
  # unavailable, so every later grant has to name the repositories it covers
  # instead of handing out the whole registry.
  role_assignment_mode = "AbacRepositoryPermissions"

  # Private endpoints are a later step. Until they exist the registry is reachable
  # over the public network, but only with an Entra ID token.
  public_network_access_enabled = true
}
