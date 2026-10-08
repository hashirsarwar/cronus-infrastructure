variable "name" {
  description = "Name of the cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "Cluster names must be 1 to 63 characters, lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Resource group that the cluster is created in. The nodes go into a separate resource group that AKS creates and names."
  type        = string
}

variable "location" {
  description = "Azure region of the cluster. Has to match the region of the resource group and of the subnet."
  type        = string
}

variable "dns_prefix" {
  description = "Prefix for the API server's DNS name. AKS appends a hash and the region, giving <prefix>-<hash>.<region>.azmk8s.io, so it does not have to be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$", var.dns_prefix))
    error_message = "DNS prefixes must be 1 to 54 characters, lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version, for example 1.35. Given as a minor alias rather than an
    exact patch, because AKS picks the newest supported patch of that minor and reports
    it separately as the current version. Pinning the minor makes an upgrade a deliberate
    edit here; leaving it out would hand the choice to whatever AKS defaults to when the
    cluster happens to be created.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.35, with no patch component."
  }
}

variable "sku_tier" {
  description = <<-EOT
    Cluster pricing tier. Free has no uptime SLA and suits nonprod; Standard buys the
    financially backed SLA and higher API server scale, and Premium buys long-term
    support. It is an environment value because that is exactly the difference between
    environments.
  EOT
  type        = string

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "subnet_id" {
  description = "Resource id of the subnet the nodes are placed in. The cluster joins this subnet but does not own it, so it belongs to the platform rather than to the cluster."
  type        = string
}

variable "api_server_subnet_id" {
  description = "Resource id of the subnet the API server is projected into. It has to be delegated to Microsoft.ContainerService/managedClusters, dedicated to this, and at least a /28. Microsoft requires the cluster identity to hold Network Contributor on it."
  type        = string
}

variable "pod_cidr" {
  description = "Address range the pods are allocated from. Overlay networking keeps pod addresses off the subnet, so this range must not overlap the virtual network or the service range."
  type        = string

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid IPv4 CIDR block, for example 10.244.0.0/16."
  }
}

variable "service_cidr" {
  description = "Address range the Kubernetes services are allocated from. Must not overlap the virtual network or the pod range."
  type        = string

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid IPv4 CIDR block, for example 10.96.0.0/16."
  }
}

variable "dns_service_ip" {
  description = "Address inside service_cidr that cluster DNS answers on. Azure uses the first address in the range for the default Kubernetes service, so this one cannot be the first."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.dns_service_ip))
    error_message = "dns_service_ip must be an IPv4 address inside service_cidr, for example 10.96.0.10."
  }
}

variable "api_server_authorized_ip_ranges" {
  description = <<-EOT
    Address ranges allowed to reach the public API server, which is what keeps it off the
    open internet. An empty list would remove the restriction altogether, which is why it
    is rejected.

    Required for a public cluster and refused for a private one, because the two are
    opposite answers to the same question. A private cluster's API server has no public
    endpoint for a range to restrict; it is reached from inside the virtual network and
    from Azure's own control plane, and the way in is a role assignment rather than a
    firewall rule. An empty list is therefore only meaningful, and only accepted, when
    private_cluster_enabled is true.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = var.private_cluster_enabled || length(var.api_server_authorized_ip_ranges) > 0
    error_message = "At least one authorized IP range is required for a public cluster. An empty list would publish the API server to the internet. A private cluster takes none instead."
  }

  validation {
    condition = alltrue([
      for range in var.api_server_authorized_ip_ranges : can(cidrhost(range, 0))
    ])
    error_message = "Every authorized IP range must be a valid IPv4 CIDR block, for example 88.97.179.44/32."
  }
}

variable "private_cluster_enabled" {
  description = <<-EOT
    Whether the cluster is private: its API server has an address inside the virtual network
    and no public one.

    This is the difference between the API server being reachable by anyone who can reach
    the authorized ranges and being reachable only from inside the virtual network and from
    Azure's own control plane. It is an environment value because it decides who can
    administer the cluster: a private cluster cannot be driven from a laptop with kubectl
    unless that laptop is on the network, so administration goes through the Azure control
    plane instead — `az aks command invoke` — or through whatever runs inside the cluster.

    Changing this forces a new cluster, so it is a decision to make once.
  EOT
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = <<-EOT
    Which private DNS zone publishes the private API server's address.

    `System` has AKS create and manage the zone, which is the whole of what a cluster whose
    clients are all inside the virtual network needs. `None` means the zone is brought and
    operated separately, which is for a design that already has a private DNS
    infrastructure of its own. A zone resource id names one of those.

    Only meaningful when private_cluster_enabled is true, and changing it forces a new
    cluster.
  EOT
  type        = string
  default     = null

  validation {
    condition = var.private_dns_zone_id == null || contains(["System", "None"], var.private_dns_zone_id) || can(regex(
      "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/[^/]+$",
      var.private_dns_zone_id
    ))
    error_message = "private_dns_zone_id must be System, None, or the resource id of a private DNS zone."
  }

  validation {
    condition     = var.private_dns_zone_id == null || var.private_cluster_enabled
    error_message = "private_dns_zone_id only applies to a private cluster. Set private_cluster_enabled, or leave the DNS zone unset, which is what a public cluster wants."
  }
}

variable "control_plane_identity" {
  description = "The identity the control plane acts as. Its principal id is what role assignments are made to."
  type = object({
    id           = string
    principal_id = string
  })
}

variable "kubelet_identity" {
  description = <<-EOT
    The identity the kubelet acts as, used to pull images and read other Azure resources.
    Created outside the cluster so that it outlives it, and so that it can be granted
    access before the cluster exists.
  EOT
  type = object({
    id        = string
    client_id = string
    object_id = string
  })
}

variable "cluster_admin_groups" {
  description = <<-EOT
    Entra ID groups granted cluster administrator through Azure RBAC, keyed by a stable
    label such as aks_admins. They are granted Azure Kubernetes Service RBAC Cluster Admin
    at the cluster scope rather than being listed as the cluster's admin group, so that
    Azure RBAC stays the single place authorization is decided.

    Local accounts are disabled, so without at least one group nobody can reach the
    cluster with kubectl, including whoever applied it. The key becomes the instance
    address in state, which is why it is a label rather than the group's object id.
  EOT
  type        = map(string)

  validation {
    condition     = length(var.cluster_admin_groups) > 0
    error_message = "At least one cluster administrator group is required, because local Kubernetes accounts are disabled."
  }

  validation {
    condition = alltrue([
      for object_id in values(var.cluster_admin_groups) :
      can(regex("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", lower(object_id)))
    ])
    error_message = "Every group must be an Entra ID object id, a GUID such as 75dcd597-6106-4419-a09a-870afabbef10."
  }
}

variable "gateway_api" {
  description = <<-EOT
    Ingress through the Kubernetes Gateway API, served by the Application Routing add-on.

    These are the two settings of the add-on's ingress profile that azurerm has no argument
    for, so they are the whole of what azapi_update_resource writes. Everything else about
    the add-on — that it is enabled at all, and that its nginx controller is not created —
    is stated by the web_app_routing block in main.tf, which the provider does have
    arguments for.

    `installation` installs the Gateway API custom resource definitions from the standard
    release channel. The implementation below requires them, and only standard channel
    CRDs are permitted: the add-on's operator looks for them and gets stuck in a crash
    loop without them.

    `app_routing_istio_mode` turns on the sidecar-less Istio control plane that reconciles
    Gateway resources for ingress. It is not the Istio service mesh add-on, and the two
    cannot be enabled together: there is no sidecar injection, no mTLS and no traffic
    management between services, only ingress. Nothing here writes serviceMeshProfile, so
    this cannot turn a mesh on.
  EOT
  type = object({
    installation           = string
    app_routing_istio_mode = string
  })

  validation {
    condition     = contains(["Standard", "Disabled"], var.gateway_api.installation)
    error_message = "installation must be Standard or Disabled. Only the standard Gateway API release channel may be installed."
  }

  validation {
    condition     = contains(["Enabled", "Disabled"], var.gateway_api.app_routing_istio_mode)
    error_message = "app_routing_istio_mode must be Enabled or Disabled."
  }
}

variable "key_vault_secrets_provider" {
  description = <<-EOT
    The Secrets Store CSI driver add-on, which mounts Key Vault objects into pods as files
    rather than as Kubernetes secrets. The Application Routing add-on reads its ingress
    certificate from a vault through it.

    `secret_rotation_enabled` turns on polling of the mounted objects, so a rotated secret
    or certificate reaches a running pod without a restart. With it off the driver still
    mounts, but a pod keeps whatever it mounted until it is restarted.

    `secret_rotation_interval` is the polling interval, written as a Go duration such as 2m
    or 1h. The provider parses it and rejects a value it cannot read or one that is negative,
    so nothing here re-checks the format. The provider also enforces that at least one of the
    two fields is set, because a block with neither does not describe an enabled add-on.
  EOT
  type = object({
    secret_rotation_enabled  = bool
    secret_rotation_interval = string
  })
}

variable "monitoring" {
  description = <<-EOT
    What the cluster collects and where it goes. Both workspaces are created by the
    observability module and passed in here, because the cluster is what writes to them and
    the two modules would otherwise have to refer to each other.

    `container_insights_streams` is the list of streams Container Insights collects. It is
    the one place the metrics/logs split is stated, and the validation below holds it to
    the logs half of it.

    `metric_annotations_allowlist` and `metric_labels_allowlist` are comma-separated lists of
    Kubernetes annotation and label keys that managed Prometheus carries as dimensions on the
    metrics it scrapes. Each distinct combination becomes its own time series, so leaving them
    unset is the smallest and cheapest configuration, and adding a key is a deliberate
    widening. They are optional rather than defaulted to an empty string because the provider
    refuses an empty string outright: an absent value means the same thing and is accepted.
  EOT
  type = object({
    log_analytics_workspace_id   = string
    azure_monitor_workspace_id   = string
    container_insights_streams   = list(string)
    metric_annotations_allowlist = optional(string)
    metric_labels_allowlist      = optional(string)
  })

  # Managed Prometheus already collects these, and Container Insights collecting them too
  # would mean the same metrics stored and billed twice, in two stores that can disagree.
  # The rule below is what keeps the split: Container Insights gets the log streams, and the
  # metric streams belong to the Prometheus rule in monitoring.tf.
  validation {
    condition = alltrue([
      for stream in var.monitoring.container_insights_streams :
      !contains(["Microsoft-Perf", "Microsoft-InsightsMetrics"], stream)
    ])
    error_message = "Container Insights must not collect Microsoft-Perf or Microsoft-InsightsMetrics: managed Prometheus already collects metrics, and collecting them twice stores and bills them twice."
  }

  validation {
    condition     = length(var.monitoring.container_insights_streams) > 0
    error_message = "container_insights_streams must name at least one stream, or the Container Insights rule would collect nothing."
  }

  validation {
    condition = alltrue([
      for id in [
        var.monitoring.log_analytics_workspace_id,
        var.monitoring.azure_monitor_workspace_id,
      ] : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", id))
    ])
    error_message = "Both workspace arguments must be resource ids, as the observability module's outputs are."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant that cluster sign-in is checked against."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.tenant_id)))
    error_message = "tenant_id must be a GUID."
  }
}

variable "system_node_pool" {
  description = <<-EOT
    The pool that runs the cluster's own add-ons. It is created with the cluster and
    carries the taint that keeps application pods off it, so it is sized for the add-ons
    rather than for workloads.
  EOT
  type = object({
    name      = string
    vm_size   = string
    min_count = number
    max_count = number
    zones     = list(string)
  })

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.system_node_pool.name))
    error_message = "Node pool names must be 1 to 12 characters, lowercase letters and digits, and must start with a letter."
  }

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.max_count >= var.system_node_pool.min_count
    error_message = "The system pool needs a minimum of at least 1 and a maximum no lower than the minimum."
  }

  validation {
    condition = alltrue([
      for zone in var.system_node_pool.zones : can(regex("^[1-9][0-9]?$", zone))
    ])
    error_message = "Availability zones are numbers, for example [\"1\", \"3\"]."
  }
}

variable "user_node_pools" {
  description = <<-EOT
    The pools that application workloads run on, keyed by a stable label such as workers.
    A map rather than a fixed object because the set differs per environment, the same way
    workload identities and databases do. Keys become the instance addresses in state, so
    they should describe the pool rather than repeat its name.
  EOT
  type = map(object({
    name        = string
    vm_size     = string
    min_count   = number
    max_count   = number
    zones       = list(string)
    node_labels = optional(map(string), {})
    node_taints = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for pool in var.user_node_pools : can(regex("^[a-z][a-z0-9]{0,11}$", pool.name))
    ])
    error_message = "Node pool names must be 1 to 12 characters, lowercase letters and digits, and must start with a letter."
  }

  validation {
    condition = alltrue([
      for pool in var.user_node_pools : pool.min_count >= 0 && pool.max_count >= pool.min_count
    ])
    error_message = "Every user pool needs a maximum no lower than its minimum."
  }

  validation {
    condition = alltrue(flatten([
      for pool in var.user_node_pools : [
        for zone in pool.zones : can(regex("^[1-9][0-9]?$", zone))
      ]
    ]))
    error_message = "Availability zones are numbers, for example [\"1\", \"3\"]."
  }
}

variable "tags" {
  description = "Tags applied to the cluster. Node pools inherit the cluster's tags."
  type        = map(string)
  default     = {}
}
