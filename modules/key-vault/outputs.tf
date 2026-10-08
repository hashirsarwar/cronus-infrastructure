output "id" {
  description = "Resource id of the vault, for role assignments scoped to it."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Name of the vault."
  value       = azurerm_key_vault.this.name
}

output "uri" {
  description = "Vault URI that clients read secrets from, for example https://kv-cronus-nonprod.vault.azure.net/."
  value       = azurerm_key_vault.this.vault_uri
}
