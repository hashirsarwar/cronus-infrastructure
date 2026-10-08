variable "subscription_id" {
  description = <<-EOT
    Subscription that hosts the shared Terraform state. It is set explicitly
    rather than inherited from the Azure CLI, so that state can never end up in
    whichever subscription happens to be active when the apply runs.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.subscription_id)))
    error_message = "subscription_id must be a GUID, for example 2781f7e7-99a8-45a0-8d55-cb37c0556b30."
  }
}

variable "location" {
  description = "Azure region for the state resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Resource group that holds the state storage account."
  type        = string
  default     = "rg-cronus-tfstate"
}

variable "storage_account_name" {
  description = "Storage account that holds the state of every environment."
  type        = string
  default     = "cronustfstate001"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names must be 3 to 24 characters long and contain only lowercase letters and digits."
  }
}

variable "container_name" {
  description = "Blob container that holds the state files."
  type        = string
  default     = "tfstate"
}

variable "state_access_principals" {
  description = <<-EOT
    Additional principals that may read and write state, such as the service
    principal used by CI. Keyed by a short logical name, so that adding or
    removing one does not disturb the others. principal_type is optional and
    accepts User, Group, ServicePrincipal or Application; leave it unset to let
    Entra ID resolve the type from the object id.
  EOT
  type = map(object({
    object_id      = string
    principal_type = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for principal in values(var.state_access_principals) :
      can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(principal.object_id)))
    ])
    error_message = "Every state_access_principals entry needs an Entra ID object id formatted as a GUID."
  }
}

variable "grant_applying_principal_state_access" {
  description = <<-EOT
    Grant the principal that applies this configuration the Storage Blob Data
    Contributor role on the state account. Disable only when that access is
    managed elsewhere, because without it no environment can be initialised.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource created here."
  type        = map(string)
  default = {
    project    = "cronus"
    managed_by = "terraform"
    purpose    = "terraform-state"
  }
}
