output "id" {
  description = "Resource id of the server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "fqdn" {
  description = "Server FQDN, which is the private DNS zone name. It resolves to the private address from inside the linked virtual network, and nowhere else."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "private_dns_zone_id" {
  description = "Resource id of the private DNS zone holding the server's record."
  value       = azurerm_private_dns_zone.this.id
}

output "database_names" {
  description = "Database names, keyed by application environment and service."
  value       = { for purpose, database in azurerm_postgresql_flexible_server_database.this : purpose => database.name }
}

# Read back rather than restated. A zone named in configuration is an instruction sent when the
# server is created, so what was asked for and what the server has are two different things —
# and after a failover they are not even the same server, because promoting the standby swaps
# the two zones. Only what Azure reports is true.
output "zone" {
  description = "The availability zone the primary server actually occupies, read back from Azure. This is where it is now, not necessarily where it was created."
  value       = azurerm_postgresql_flexible_server.this.zone
}

output "high_availability_mode" {
  description = "High availability mode the server actually has, as reported back. Null when no high availability was requested."
  value       = try(azurerm_postgresql_flexible_server.this.high_availability[0].mode, null)
}
