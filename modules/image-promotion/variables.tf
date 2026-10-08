variable "source_registry_id" {
  description = <<-EOT
    Resource id of the registry images are promoted from. It belongs to another
    environment, so it is passed in rather than read with a data source: a data source
    would make this configuration fail to plan whenever that environment is not there to
    be read, which is the opposite of being independently deployable.
  EOT
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft[.]ContainerRegistry/registries/[^/]+$", var.source_registry_id))
    error_message = "source_registry_id must be a container registry resource id, for example /subscriptions/<id>/resourceGroups/rg-cronus-nonprod/providers/Microsoft.ContainerRegistry/registries/acrcronusnonprod."
  }
}

variable "destination_registry_id" {
  description = "Resource id of the registry images are promoted into. It is in this environment, and the import role and its assignment are created against it."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft[.]ContainerRegistry/registries/[^/]+$", var.destination_registry_id))
    error_message = "destination_registry_id must be a container registry resource id, for example /subscriptions/<id>/resourceGroups/rg-cronus-prod/providers/Microsoft.ContainerRegistry/registries/acrcronusprod."
  }
}

variable "role_definition_name" {
  description = <<-EOT
    Display name of the import role definition — the one that triggers the copy *into* the
    destination registry. Custom role names have to be unique in the tenant, so a second
    environment creating one needs a second name rather than a second copy of this one.
  EOT
  type        = string

  validation {
    condition     = length(var.role_definition_name) > 0
    error_message = "role_definition_name must not be empty."
  }
}

variable "source_read_role_definition_name" {
  description = <<-EOT
    Display name of the role definition that grants read of the source registry's own ARM
    resource — a different thing from reading an image inside it, and the permission an
    import needs from the caller on the registry it is copying from.

    A role definition of its own rather than the built-in `Reader`, so that what is granted
    is one action on one registry. Custom role names have to be unique in the tenant.
  EOT
  type        = string

  validation {
    condition     = length(var.source_read_role_definition_name) > 0
    error_message = "source_read_role_definition_name must not be empty."
  }
}

variable "role_definition_scope" {
  description = <<-EOT
    Scope the import role definition is created at, and the widest scope it may be assigned
    within. Azure accepts a subscription or a resource group here and not a narrower
    resource, so the registry is a scope an assignment can be made against rather than a
    scope the definition itself can live at. Nothing is granted by naming a scope here: the
    assignment is still made against the registry alone.
  EOT
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+(/resourceGroups/[^/]+)?$", var.role_definition_scope))
    error_message = "role_definition_scope must be a subscription id or a resource group id, for example /subscriptions/<id> or /subscriptions/<id>/resourceGroups/rg-cronus-prod."
  }
}

variable "promoters" {
  description = <<-EOT
    Principals allowed to promote an image from the source registry into the destination
    registry, keyed by a label such as the application's release identity.

    Each one is granted read of the named repositories in the source, and the ability to
    trigger an import in the destination. Both are narrowed to the repositories named here,
    which is what keeps one application's release identity to its own images: the read is an
    ABAC condition, and the import is a role definition that carries only the actions the
    operation needs and no repository data actions at all.

    The key becomes the instance address in state.
  EOT
  type = map(object({
    principal_id   = string
    principal_type = optional(string)
    repositories   = list(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for promoter in values(var.promoters) : length(promoter.repositories) > 0
    ])
    error_message = "Every promoter needs at least one repository. An empty list would leave the source-read condition with nothing to match, granting the whole registry instead of one repository."
  }

  validation {
    condition = alltrue(flatten([
      for promoter in values(var.promoters) : [
        for repository in promoter.repositories :
        can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", repository))
      ]
    ]))
    error_message = "Every repository must be a valid container registry repository name: lowercase letters and digits separated by ., _, - or /, for example cronus-web."
  }
}
