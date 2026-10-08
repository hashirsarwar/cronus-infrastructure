# Remote state shared by every Cronus environment.
#
# This configuration is applied once. The environments under ../environments
# never create these resources themselves; they only name the storage account in
# their backend blocks.

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  account_tier = "Standard"

  # Zone-redundant, because this account holds the state of every environment.
  account_replication_type = "ZRS"

  # Public network access stays enabled until private endpoints exist: state has
  # to be reachable from a laptop and from a hosted runner. Anonymous blob access
  # is off and the container is private regardless.
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access           = "Enabled"

  # State is read and written with Entra ID only. A shared key would grant access
  # to every environment's state at once, cannot be scoped to one environment,
  # and leaves no record of who used it.
  shared_access_key_enabled = false

  # Versioning and soft delete are the safety net for the one artefact that
  # cannot be regenerated: a truncated or corrupted state file.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Whoever applies this configuration has to be able to read the state again
# afterwards, otherwise no environment can be initialised.
resource "azurerm_role_assignment" "applying_principal" {
  count = var.grant_applying_principal_state_access ? 1 : 0

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# CI service principals and any other principal that must read or write state.
resource "azurerm_role_assignment" "state_access" {
  for_each = var.state_access_principals

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.object_id
  principal_type       = each.value.principal_type
}
