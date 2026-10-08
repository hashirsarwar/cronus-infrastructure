variable "subscription_id" {
  description = "Subscription that prod Cronus resources are deployed into. It does not have to be the subscription that holds the state, though today it is the same one nonprod uses — the separation between the environments is by resource group and network, not by subscription."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.subscription_id)))
    error_message = "subscription_id must be a GUID, for example 2781f7e7-99a8-45a0-8d55-cb37c0556b30."
  }
}

variable "location" {
  description = "Azure region for production resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Resource group that holds the production environment. Separate from nonprod's, so nothing is shared by accident and a mistake in one cannot be a mistake in the other."
  type        = string
}

variable "vnet_name" {
  description = "Name of the production virtual network. Production is not peered to nonprod: the networks are separate boundaries, and their address spaces do not overlap so that a peer is possible later without renumbering."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space of the production virtual network. It has to differ from every other environment's range."
  type        = list(string)
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for each production subnet. See ../../modules/networking/README.md."
  type = object({
    aks               = list(string)
    aks_apiserver     = list(string)
    postgres          = list(string)
    private_endpoints = list(string)
  })
}

variable "public_ingress" {
  description = <<-EOT
    Ports the cluster's public edge accepts TCP from the internet on. Empty for production
    until it has an edge: an NSG rule that admits port 80 to the node subnet is exposure
    with nothing behind it until a Gateway exists, and the edge milestone is the change that
    adds the rule rather than this one.

    Each entry names its port and the rule's name; see the networking module for why the name
    is stated rather than derived.
  EOT
  type = list(object({
    port = number
    name = string
  }))
  default = []
}

variable "tags" {
  description = "Tags applied to every production resource that supports them."
  type        = map(string)
  default = {
    project     = "cronus"
    environment = "prod"
    managed_by  = "terraform"
  }
}

variable "acr_name" {
  description = "Name of the production container registry. Globally unique, letters and digits only. Production has its own rather than pulling from nonprod's, so an image can only reach production by being published into a registry whose writers were granted exactly that."
  type        = string
}

variable "acr_sku" {
  description = "Registry SKU. Private link needs Premium, so this changes if private endpoints are ever added."
  type        = string
}

variable "key_vault_name" {
  description = "Name of the production key vault. Globally unique."
  type        = string
}

variable "key_vault_soft_delete_retention_days" {
  description = "Days a deleted production vault or secret stays recoverable."
  type        = number
}

variable "key_vault_purge_protection_enabled" {
  description = "Whether a deleted production vault is protected from being purged early. On here: purge protection is the difference between a deletion being recoverable and being final, and production is where that matters."
  type        = bool
}

variable "aks_identity_names" {
  description = "Names of the cluster's managed identities. See ../../modules/identities/README.md."
  type = object({
    controlplane = string
    kubelet      = string
  })
}

variable "workload_identity_names" {
  description = "Workload identity names, keyed by application environment and service. Production carries one application environment, so the keys are ordering_prod and delivery_prod."
  type        = map(string)
}

variable "migration_identity_names" {
  description = "Migration identity names, keyed by the same application environment and service keys as workload_identity_names."
  type        = map(string)
}

variable "workload_federated_credentials" {
  description = <<-EOT
    Federated identity credentials for the production workloads, keyed by the credential's
    name in Microsoft Entra ID. The subject names the Kubernetes namespace and service
    account that will present the token, which cronus-gitops owns, so these strings have
    to agree with that repository.

    The issuer is this cluster's, so a token from the nonprod cluster is not accepted here
    however the subject is spelled.
  EOT
  type = map(object({
    identity = string
    subject  = string
  }))
}

variable "migration_federated_credentials" {
  description = <<-EOT
    Federated identity credentials for the migration identities, keyed by the credential's
    name in Microsoft Entra ID. The subject names a Kubernetes namespace and service
    account that cronus-gitops owns, and it is deliberately not the account the deployment
    runs as, so a pod serving traffic cannot assume the identity that changes the schema.
  EOT
  type = map(object({
    identity = string
    subject  = string
  }))
}

variable "promotion_source" {
  description = <<-EOT
    The registry a production image is promoted from, named as its parts rather than as a
    resource id so that a source in another subscription is a change to one field and not a
    change to a string.

    It belongs to nonprod, and it is stated here rather than read with a data source on
    purpose. A data source would make production fail to plan whenever nonprod is not there
    to be read, which is a dependency production is supposed to be free of; what production
    owns is a grant on that registry, not the registry.
  EOT
  type = object({
    subscription_id     = string
    resource_group_name = string
    registry_name       = string
  })
}

variable "import_role_definition_name" {
  description = "Display name of the custom role that triggers an image import into the production registry. Custom role names have to be unique in the tenant."
  type        = string
}

variable "source_read_role_definition_name" {
  description = "Display name of the custom role that grants read of the nonprod registry's own ARM resource, which an import needs from the registry it copies from. Custom role names have to be unique in the tenant."
  type        = string
}

variable "github_ci" {
  description = <<-EOT
    One row per application whose continuous integration publishes to the production
    registry, keyed by the application. Each row states the three names that have to agree:
    the identity in Azure, the subject GitHub issues for the repository that may assume it,
    and the registry repository the images are pushed to.

    These are production's own identities, distinct from nonprod's, so the ability to
    publish an image that production will run is granted here and not inherited from a
    repository's nonprod access.

    The subject is written out rather than templated because it has to match the token
    GitHub actually signs. Repositories created after 15 July 2026 carry immutable
    subjects naming the owner and repository by id, and GitHub will not issue the shorter
    form for them.
  EOT
  type = map(object({
    identity_name  = string
    subject        = string
    acr_repository = string
  }))
}

variable "postgres_server_name" {
  description = "Name of the production PostgreSQL server. It is part of the FQDN, so it has to be globally unique. Production does not share nonprod's server."
  type        = string
}

variable "postgres_private_dns_zone_name" {
  description = "Name of the private DNS zone that publishes the production server's address. The zone name becomes the server's FQDN, so this is the hostname the applications connect to."
  type        = string
}

variable "postgres_version" {
  description = "Major version of PostgreSQL."
  type        = string
}

variable "postgres_sku_name" {
  description = "Server SKU. It cannot be a Burstable SKU: zone-redundant high availability is not offered on that tier, and the smallest General Purpose SKU is the floor for this environment."
  type        = string

  validation {
    condition     = !can(regex("^B_", var.postgres_sku_name))
    error_message = "postgres_sku_name must not be a Burstable SKU. Zone-redundant high availability is not supported on Burstable, and production runs with it on."
  }
}

variable "postgres_storage_mb" {
  description = "Server storage in MiB, which cannot be shrunk later. Storage size also sets the provisioned IOPS, so this is a performance decision as well as a capacity one."
  type        = number
}

variable "postgres_backup_retention_days" {
  description = "Days of automated backups to keep, and with them the point-in-time restore window. The service accepts 7 to 35."
  type        = number

  validation {
    condition     = var.postgres_backup_retention_days >= 7 && var.postgres_backup_retention_days <= 35
    error_message = "postgres_backup_retention_days must be between 7 and 35."
  }
}

variable "postgres_geo_redundant_backup_enabled" {
  description = "Whether backups are replicated to the paired region, which is UK West for UK South. On here, and it has to be decided now rather than later: the service does not allow the backup storage redundancy to be changed after a server is provisioned, so turning it on afterwards means a new server."
  type        = bool
}

variable "postgres_zone" {
  description = <<-EOT
    Availability zone to place the production server in, or null to let Azure choose.

    Named here because a server already exists and this is where Azure put it: the value is
    an agreement with reality, not a request for a change. It is sent when a server is
    created and read back afterwards, so it states the intended placement for a rebuild and
    is never used to move the server that exists.

    Set it to null only if the server were rebuilt and Azure's choice was wanted instead.
  EOT
  type        = string
  default     = null
}

variable "postgres_high_availability" {
  description = "High availability for the production server. See the postgres module for what the modes mean and what a standby costs."
  type = object({
    mode                      = string
    standby_availability_zone = optional(string)
  })
  default = null
}

variable "admin_groups" {
  description = <<-EOT
    Entra ID security groups that administer something, keyed by purpose. The identities
    module creates them, and whatever they administer is handed their object id, so no
    individual account ever owns the way in to a database or a cluster. Members are
    listed explicitly rather than derived from whoever runs Terraform, so who can
    administer what is reviewed like any other change and an automated run cannot add
    itself. The key becomes the instance address in state.

    These are production's groups and are not shared with nonprod, so the ability to
    administer production is granted here rather than following from nonprod membership.
  EOT
  type = map(object({
    name        = string
    description = string
    members     = set(string)
  }))

  validation {
    condition = alltrue(flatten([
      for group in values(var.admin_groups) : [
        for object_id in group.members :
        can(regex("^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", lower(object_id)))
      ]
    ]))
    error_message = "Every group member must be an Entra ID object id, a GUID such as 27559288-f428-4435-9b9d-5904ae94fe4d."
  }

  validation {
    condition     = alltrue([for group in values(var.admin_groups) : length(group.members) > 0])
    error_message = "Every administrator group needs at least one member. An empty group grants nothing, and these groups are the only way in to what they administer."
  }
}

variable "postgres_database_names" {
  description = "Databases to create, keyed by application environment and service."
  type        = map(string)
}

variable "aks_cluster_name" {
  description = "Name of the production Kubernetes cluster."
  type        = string
}

variable "aks_dns_prefix" {
  description = "Prefix for the cluster's API server DNS name. AKS appends a hash and the region."
  type        = string
}

variable "aks_kubernetes_version" {
  description = "Kubernetes minor version for production, for example 1.35. AKS picks the newest patch of that minor; raising this is how the cluster is upgraded."
  type        = string
}

variable "aks_sku_tier" {
  description = "Cluster pricing tier for production. Standard buys the financially backed uptime SLA, which is the point of choosing it here."
  type        = string
}

variable "aks_pod_cidr" {
  description = "Address range pods are allocated from. Overlay keeps it off the virtual network, so it must not overlap the virtual network or the service range, and it cannot be changed after creation. Production uses a range of its own rather than nonprod's, so that two clusters' ranges could never be confused if the networks are ever peered."
  type        = string
}

variable "aks_service_cidr" {
  description = "Address range Kubernetes services are allocated from. Must not overlap the virtual network or the pod range."
  type        = string
}

variable "aks_dns_service_ip" {
  description = "Address inside the service range that cluster DNS answers on."
  type        = string
}

variable "aks_private_cluster_enabled" {
  description = "Whether the production cluster is private. True from the first apply: there is no bootstrap window in which the API server is public, and none is wanted."
  type        = bool
}

variable "aks_private_dns_zone_id" {
  description = "Which private DNS zone publishes the API server's private address. System is AKS managing the zone, which is all a cluster whose clients are all inside the virtual network needs — including the nodes, which reach the API server through its internal load balancer address without DNS at all."
  type        = string
  default     = null
}

variable "aks_api_server_authorized_ip_ranges" {
  description = "Address ranges allowed to reach the API server. Empty for production, and required to be empty: the API server is private, so there is no public endpoint for a range to restrict. Azure refuses the two together, and the AKS module refuses them here rather than leaving the failure to the ARM API."
  type        = list(string)
  default     = []
}

variable "aks_system_node_pool" {
  description = "The pool running the cluster's add-ons. See ../../modules/aks/README.md for why its zones are environment-specific."
  type = object({
    name      = string
    vm_size   = string
    min_count = number
    max_count = number
    zones     = list(string)
  })
}

variable "aks_user_node_pools" {
  description = "The pools application workloads run on, keyed by a stable label such as workers."
  type = map(object({
    name        = string
    vm_size     = string
    min_count   = number
    max_count   = number
    zones       = list(string)
    node_labels = optional(map(string), {})
    node_taints = optional(list(string), [])
  }))
}

variable "aks_gateway_api" {
  description = "Gateway API ingress support on the cluster. Application Routing is enabled, and its nginx controller kept uncreated, by the module rather than from here. See ../../modules/aks/README.md."
  type = object({
    installation           = string
    app_routing_istio_mode = string
  })
}

variable "aks_key_vault_secrets_provider" {
  description = "Secrets Store CSI driver settings. See ../../modules/aks/README.md for why the Application Routing add-on needs it. The provider parses the interval and rejects a value it cannot read, so it is not re-checked here."
  type = object({
    secret_rotation_enabled  = bool
    secret_rotation_interval = string
  })
}

variable "log_analytics_workspace_name" {
  description = "Name of the production Log Analytics workspace, which holds container logs, Kubernetes events and production Application Insights. Nonprod telemetry does not land here and production telemetry does not land in nonprod's."
  type        = string
}

variable "azure_monitor_workspace_name" {
  description = "Name of the production Azure Monitor workspace, which holds Prometheus metrics."
  type        = string
}

variable "log_analytics_retention_in_days" {
  description = "How long the production Log Analytics workspace keeps data. See ../../modules/observability/README.md."
  type        = number
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion cap for the production Log Analytics workspace, in gigabytes, or -1 for none. See ../../modules/observability/README.md and terraform.tfvars for what this value is protecting against."
  type        = number
}

variable "container_insights_streams" {
  description = "The streams Container Insights collects for production. The module refuses the metric streams, because managed Prometheus already collects those. See ../../modules/aks/README.md."
  type        = list(string)
}

variable "metric_annotations_allowlist" {
  description = "Comma-separated Kubernetes annotation keys managed Prometheus carries as metric dimensions. Unset adds none, which is the cheapest setting; the provider rejects an empty string, so absence is how to say 'none'."
  type        = string
  default     = null
}

variable "metric_labels_allowlist" {
  description = "Comma-separated Kubernetes label keys managed Prometheus carries as metric dimensions. Unset adds none, which is the cheapest setting; the provider rejects an empty string, so absence is how to say 'none'."
  type        = string
  default     = null
}

variable "alert_action_group_name" {
  description = "Name of the production Action Group that alert rules notify."
  type        = string
}

variable "alert_action_group_short_name" {
  description = "Short name of the production Action Group, at most 12 characters. See ../../modules/alerting/README.md."
  type        = string
}

variable "alert_email_receivers" {
  description = <<-EOT
    Email addresses notified when a production alert fires. This is the only place a
    recipient is named: the module takes a list, so changing who is told is a change to
    this value and nothing else. At least one address is required.

    Separate from nonprod's list on purpose. An alert that pages someone about a
    development cluster and one that pages them about production should not be the same
    decision.
  EOT
  type        = list(string)
}

variable "alert_thresholds" {
  description = "Tuning for the production alert rules. The module holds defaults tuned to stay quiet on a development cluster; production sets its own. See ../../modules/alerting/README.md before overriding one."
  type = object({
    node_cpu_percent      = optional(number)
    node_cpu_for          = optional(string)
    node_memory_percent   = optional(number)
    node_memory_for       = optional(string)
    node_not_ready_for    = optional(string)
    crashloop_for         = optional(string)
    restarts_threshold    = optional(number)
    restarts_window       = optional(string)
    restarts_for          = optional(string)
    oom_for               = optional(string)
    ready_ratio_threshold = optional(number)
    ready_state_for       = optional(string)
  })
  default = {}
}

variable "application_insights" {
  description = "Application Insights resources for production, keyed by environment and service. See ../../modules/observability/README.md."
  type        = map(string)
}
