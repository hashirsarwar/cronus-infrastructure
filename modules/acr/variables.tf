variable "name" {
  description = "Name of the registry. Container registry names are globally unique, alphanumeric only, and 5 to 50 characters long."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "Registry names must be 5 to 50 characters, letters and digits only, with no hyphens or underscores."
  }
}

variable "resource_group_name" {
  description = "Resource group that the registry is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the registry. Has to match the region of the resource group."
  type        = string
}

variable "sku" {
  description = "Registry SKU, which decides which features the registry can use. Check the module README before relying on private link, geo-replication or zone redundancy."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of Basic, Standard or Premium."
  }
}

variable "repository_readers" {
  description = <<-EOT
    Principals allowed to pull from every repository in the registry, keyed by a label
    such as the cluster's kubelet identity. They are granted Container Registry
    Repository Reader rather than AcrPull, because this registry is in ABAC mode: the
    legacy AcrPull role is not honoured there, and the grant has to be the repository
    read data actions instead. The key becomes the instance address in state.

    There is deliberately no repository scoping here. The cluster pulls whatever it runs,
    so limiting it to the images it happens to run today would break the next deployment.
  EOT
  type = map(object({
    principal_id   = string
    principal_type = optional(string)
  }))
  default = {}
}

variable "repository_writers" {
  description = <<-EOT
    Principals allowed to push images, keyed by a label such as the application's CI
    identity. They are granted Container Registry Repository Writer, narrowed by an ABAC
    condition to the repositories listed for each one, so a continuous integration
    identity for one application cannot overwrite another application's images.

    Restricting them is the point of the ABAC mode this registry runs in. Without a
    condition, an ABAC-enabled role grants the whole registry, which is what the role's
    own documentation warns about.
  EOT
  type = map(object({
    principal_id   = string
    principal_type = optional(string)
    repositories   = list(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for writer in values(var.repository_writers) : length(writer.repositories) > 0
    ])
    error_message = "Every writer needs at least one repository. An empty list would leave the condition with nothing to match, granting the whole registry instead of one repository."
  }

  validation {
    condition = alltrue(flatten([
      for writer in values(var.repository_writers) : [
        for repository in writer.repositories :
        can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", repository))
      ]
    ]))
    error_message = "Every repository must be a valid container registry repository name: lowercase letters and digits separated by ., _, - or /, for example cronus-web."
  }
}

variable "tags" {
  description = "Tags applied to the registry."
  type        = map(string)
  default     = {}
}
