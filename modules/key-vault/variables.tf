variable "name" {
  description = "Name of the vault. Key Vault names are globally unique, 3 to 24 characters, and may contain letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.name))
    error_message = "Vault names must be 3 to 24 characters, letters, digits and hyphens only."
  }
}

variable "resource_group_name" {
  description = "Resource group that the vault is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the vault. Has to match the region of the resource group."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant that owns the vault, and the identities that will later be granted access to it."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.tenant_id)))
    error_message = "tenant_id must be a GUID."
  }
}

variable "soft_delete_retention_days" {
  description = "How long a deleted vault or secret stays recoverable. With purge protection on, that period is inescapable and the vault name stays reserved for its duration."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  description = <<-EOT
    Whether a deleted vault is protected from being purged before its retention
    period ends. Prod should keep this on, where losing the vault permanently is
    worse than waiting. Nonprod turns it off so that a deleted vault can be purged
    and its name reused straight away, without waiting out the retention period.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}
