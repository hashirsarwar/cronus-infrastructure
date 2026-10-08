variable "resource_group_name" {
  description = "Resource group that the virtual network is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the virtual network. Has to match the region of the resource group."
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network."
  type        = string
}

variable "address_space" {
  description = "Address space of the virtual network. Every subnet prefix has to fall inside it; that is checked by Azure rather than here."
  type        = list(string)

  validation {
    condition = alltrue([
      for prefix in var.address_space : can(cidrhost(prefix, 0))
    ])
    error_message = "address_space must contain at least one valid IPv4 CIDR block, for example 10.20.0.0/16."
  }
}

variable "subnet_address_prefixes" {
  description = <<-EOT
    Address prefixes for each of the subnets this module manages. All are required:
    each one belongs to a different part of the platform, and a missing subnet cannot
    be discovered until the module that needs it is added.
  EOT
  type = object({
    aks               = list(string)
    aks_apiserver     = list(string)
    postgres          = list(string)
    private_endpoints = list(string)
  })

  validation {
    condition = alltrue([
      for prefix in concat(
        var.subnet_address_prefixes.aks,
        var.subnet_address_prefixes.aks_apiserver,
        var.subnet_address_prefixes.postgres,
        var.subnet_address_prefixes.private_endpoints,
      ) : can(cidrhost(prefix, 0))
    ])
    error_message = "Every subnet address prefix must be a valid IPv4 CIDR block, for example 10.20.0.0/20."
  }
}

variable "public_ingress" {
  description = <<-EOT
    Ports the cluster's public edge accepts TCP from the internet on, one network security
    rule each.

    Each entry names its port and the rule's name, and the name is not decoration: a network
    security rule's name is part of its identity, so renaming one destroys it and creates
    another. Stating it here is what lets the set of published ports change — a second port
    added for TLS, an environment that publishes nothing at all — without disturbing the
    rules that already exist. It is also where a port takes the name somebody looking at the
    portal would expect to see.

    This belongs to the environment because the edge does: a port is opened when that
    environment has a listener behind it, and an environment with no public ingress — a
    production cluster before its edge exists — publishes nothing and opens nothing.

    443 is added beside 80 rather than replacing it, because the HTTP listener keeps a job
    after TLS arrives: it is what redirects to HTTPS. Issuance itself is designed around
    DNS-01, so it needs no inbound path of its own.

    An empty list is a cluster reached from inside the virtual network only.
  EOT
  type = list(object({
    port = number
    name = string
  }))
  default = [{ port = 80, name = "allow-http-inbound" }]

  validation {
    condition = alltrue([
      for rule in var.public_ingress : rule.port >= 1 && rule.port <= 65535
    ])
    error_message = "Every published port must be between 1 and 65535."
  }

  validation {
    condition     = length(var.public_ingress) == length(distinct([for rule in var.public_ingress : rule.name]))
    error_message = "Two public ingress rules share a name. Rule names identify the rules, so a repeat would be one rule with the other's port rather than two rules."
  }

  validation {
    condition = alltrue([
      for rule in var.public_ingress : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,78}[a-zA-Z0-9_]$", rule.name))
    ])
    error_message = "Every rule name must be 2 to 80 characters of letters, digits, underscores, periods and hyphens, and must start with a letter or digit."
  }

  validation {
    condition     = length(var.public_ingress) <= 100
    error_message = "At most 100 public ingress rules, because each one takes a priority from 100 upwards and the group's own rules begin at 65000."
  }
}

variable "tags" {
  description = "Tags applied to every resource created here that supports them. Subnets do not support tags."
  type        = map(string)
  default     = {}
}
