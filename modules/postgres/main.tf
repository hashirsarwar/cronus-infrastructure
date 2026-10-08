# A PostgreSQL flexible server with private access only.
#
# The server lives in the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers
# and is never reachable from the internet. Its address is published in a private DNS
# zone linked to the virtual network, which is the only way anything inside the network
# can find it.
#
# There is no local administrator. Password authentication is off and the server
# authenticates Entra ID principals only, so there is no database password to store,
# rotate or leak.
#
# High availability is an environment value rather than a decision of this module: leaving
# it null is a single server in one zone, and naming a mode is a standby in another. See
# the variable for what the difference buys and costs.
#
# Placement is an environment value for the same reason, and the two are related: the standby
# has to be in a zone the primary is not, so an environment that names one constrains the
# other. Both are stated at creation and then read back rather than enforced, because a
# failover moves them.

# Keep the private zone distinct from the server FQDN; Azure creates its records here.
# Applications use the server's fqdn output, not the zone name.
resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = var.private_dns_zone_name != "${var.name}.postgres.database.azure.com"
      error_message = "Azure refuses a private DNS zone named after the server, because that name is already the server's own DNS name. Put a label in between, as the portal does: ${var.name}.private.postgres.database.azure.com."
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                = "dnslink-postgres"
  private_dns_zone_id = azurerm_private_dns_zone.this.id
  virtual_network_id  = var.virtual_network_id
  tags                = var.tags

  # Automatic registration is for virtual machines, not for a service that
  # publishes its own record.
  registration_enabled = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  version  = var.server_version
  sku_name = var.sku_name

  storage_mb            = var.storage_mb
  auto_grow_enabled     = true
  backup_retention_days = var.backup_retention_days

  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id
  public_network_access_enabled = false

  # Where the server is placed. Sent at creation and read back afterwards, which is why the
  # resource ignores changes to it below: a named zone is an instruction to Azure on the way
  # in, not an assertion to be reconciled on every later plan. Null leaves the choice to Azure.
  zone = var.zone

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  # A second server in another zone, promoted automatically when the primary fails. Left out
  # entirely rather than set to Disabled, because an absent block is what Azure reads as off
  # and a block naming the mode is a request to configure something rather than to not.
  dynamic "high_availability" {
    for_each = var.high_availability == null ? [] : [var.high_availability]

    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = high_availability.value.standby_availability_zone
    }
  }

  # Ignore Azure-chosen placement and failover zone swaps to avoid invalid moves or standby-zone removal.
  # Keep HA mode managed so enabling or disabling HA remains an explicit change.
  lifecycle {
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

# Without this the server would have no way in at all, since there is no local
# administrator to fall back on.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  resource_group_name = var.resource_group_name
  server_name         = azurerm_postgresql_flexible_server.this.name
  tenant_id           = var.tenant_id

  object_id      = var.entra_administrator.object_id
  principal_name = var.entra_administrator.principal_name
  principal_type = var.entra_administrator.principal_type
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.database_names

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id

  # charset and collation are left at the server default because they cannot be
  # changed after the database is created.
}
