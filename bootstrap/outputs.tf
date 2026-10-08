output "resource_group_name" {
  description = "Resource group that holds the state storage account."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Storage account that holds the state of every environment."
  value       = azurerm_storage_account.state.name
}

output "container_name" {
  description = "Blob container that holds the state files."
  value       = azurerm_storage_container.state.name
}

output "backend_configuration" {
  description = "Backend block for an environment's providers.tf, with the key left to be filled in per environment."
  value       = <<-EOT
    backend "azurerm" {
      resource_group_name  = "${azurerm_resource_group.state.name}"
      storage_account_name = "${azurerm_storage_account.state.name}"
      container_name       = "${azurerm_storage_container.state.name}"
      key                  = "cronus/<environment>.tfstate"
      use_azuread_auth     = true
      use_cli              = true
    }
  EOT
}
