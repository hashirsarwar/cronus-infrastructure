resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  tags                = var.tags

  sku_name = "standard"

  # Entra ID role assignments instead of access policies. Grants are scoped,
  # auditable and managed the same way as every other Azure permission, rather
  # than through a per-vault model that exists nowhere else.
  rbac_authorization_enabled = true

  # Soft delete is always on, so a deleted vault or secret stays recoverable for
  # the retention period. Purge protection decides whether that period can be cut
  # short by purging: no for nonprod, yes for prod.
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  # Private endpoints are a later step. Until they exist the vault is reachable
  # over the public network, but only by a principal holding a role on it.
  public_network_access_enabled = true
}
