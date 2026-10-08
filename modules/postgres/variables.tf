variable "name" {
  description = "Name of the server. It becomes part of the server's FQDN, so it has to be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "Server names must be 3 to 63 characters, lowercase letters, digits and hyphens, and cannot start or end with a hyphen."
  }
}

variable "resource_group_name" {
  description = "Resource group that the server and its private DNS zone are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the server. Has to match the region of the resource group."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Resource id of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. The server takes ownership of it."
  type        = string
}

variable "virtual_network_id" {
  description = "Resource id of the virtual network that the private DNS zone is linked to, so the server resolves inside it."
  type        = string
}

variable "private_dns_zone_name" {
  description = <<-EOT
    Name of the private DNS zone that publishes the server's address. Azure accepts
    only names ending in postgres.database.azure.com, and for a server reached through
    a delegated subnet the zone name is the server's FQDN, so it is also the hostname
    applications connect to. Name it after the server, as the portal and the CLI do.
  EOT
  type        = string

  validation {
    condition     = can(regex("\\.postgres\\.database\\.azure\\.com$", var.private_dns_zone_name))
    error_message = "Azure accepts only private DNS zone names that end with .postgres.database.azure.com, for example psql-cronus-nonprod.private.postgres.database.azure.com."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant that authenticates connections to the server."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.tenant_id)))
    error_message = "tenant_id must be a GUID."
  }
}

variable "entra_administrator" {
  description = <<-EOT
    The Entra ID principal that administers the server. With password authentication
    off this is the only way in, and it is also the only principal that can create
    database roles for the workload identities afterwards.
  EOT
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.entra_administrator.principal_type)
    error_message = "principal_type must be User, Group or ServicePrincipal."
  }
}

variable "database_names" {
  description = <<-EOT
    Databases to create, keyed by the application environment and service they
    belong to, for example ordering_dev. The key is a stable label, so it can differ
    from the database name itself.
  EOT
  type        = map(string)
}

variable "server_version" {
  description = "Major version of PostgreSQL. Named server_version rather than version, because a module block reserves version for the module's own version constraint."
  type        = string
  default     = "18"
}

variable "sku_name" {
  description = "SKU, in the form <tier>_<size>, where the tier is B for Burstable, GP for General Purpose or MO for Memory Optimized: B_Standard_B1ms, GP_Standard_D2ds_v5. Burstable is the cheapest and suits nonprod, but it is the one tier that cannot have zone-redundant high availability, so a server with it must be at least General Purpose."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage in MiB. The smallest flexible server allocation is 32768, which is 32 GiB."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 7
}

variable "zone" {
  description = <<-EOT
    Availability zone to place the primary server in, or null to let Azure choose.

    Sent when the server is created and read back afterwards, never enforced: the resource
    ignores changes to `zone`, so this says where a new server should be placed and does not
    argue with where an existing one already is. Those are different questions, and a server
    that Azure placed somewhere workable is not drift to be corrected.

    It matters beyond placement, because it decides what the standby can use: Azure refuses a
    standby in the primary's zone, so naming the primary's zone constrains which zones the
    pair may occupy. A value that is stale, or a zone the subscription cannot use, fails at
    provisioning rather than degrading, which is why the default is to leave the choice to
    Azure and name one only where there is a server to agree with.

    Note that the zones a subscription is refused are per-service. A VM family can be
    unavailable in a zone that the PostgreSQL service is perfectly able to place a server
    in, so a `NotAvailableForSubscription` result from `az vm list-skus` does not predict
    this.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[1-9][0-9]?$", var.zone))
    error_message = "zone must be an availability zone number, for example 2, or left unset to let Azure choose."
  }
}

variable "high_availability" {
  description = <<-EOT
    High availability for the server, or null for none.

    None is a single server in one availability zone: a failure of that zone, or of the
    server, is an outage until it recovers. ZoneRedundant is a second server in another
    zone, kept in sync and promoted automatically, which is what turns a zone failure from
    an outage into a failover. It is roughly twice the compute cost of the same SKU without
    it, because the standby is a server of the same size.

    This is deliberately an environment value rather than a module default: nonprod is
    rebuilt rather than failed over, so paying for a standby there buys nothing, and
    production is the opposite.

    `standby_availability_zone` names the zone the standby is placed in, and is sent when the
    server is created. Left out, Azure places the standby itself. Which zones a SKU may use is
    a regional and per-SKU question, so the module does not constrain it beyond the one
    combination Azure refuses: a standby in the primary's zone.

    After creation the standby's zone is read back rather than enforced — see the resource's
    lifecycle — because a failover swaps the two servers, and a plan that argued with where
    the standby ended up would undo a working failover on the next apply.
  EOT
  type = object({
    mode                      = string
    standby_availability_zone = optional(string)
  })
  default = null

  validation {
    condition     = var.high_availability == null || contains(["SameZone", "ZoneRedundant"], var.high_availability.mode)
    error_message = "high_availability.mode must be SameZone or ZoneRedundant. Leave the whole value null for a server without high availability, rather than naming Disabled: null omits the block, which is what Azure reads as off."
  }

  validation {
    condition     = var.high_availability == null || var.high_availability.mode != "ZoneRedundant" || var.high_availability.standby_availability_zone == null || can(regex("^[1-9][0-9]?$", var.high_availability.standby_availability_zone))
    error_message = "standby_availability_zone must be an availability zone number, for example 2."
  }

  # Azure refuses the pair outright — "the zone of the server cannot be same as the standby
  # zone" — and it refuses it at provisioning, after the server has been waited on. Catching
  # it here costs nothing instead.
  validation {
    condition = (
      var.high_availability == null ||
      var.high_availability.standby_availability_zone == null ||
      var.zone == null ||
      var.high_availability.standby_availability_zone != var.zone
    )
    error_message = "The standby must be in a different availability zone from the primary: Azure refuses a standby in the primary's zone."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Whether backups are replicated to the paired region. Costs more, and is worth it where losing the region means losing the database."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource created here that supports them."
  type        = map(string)
  default     = {}
}
