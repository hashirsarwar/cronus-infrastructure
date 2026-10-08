variable "subscription_id" {
  description = "Subscription that nonprod Cronus resources are deployed into. It does not have to be the subscription that holds the state."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", lower(var.subscription_id)))
    error_message = "subscription_id must be a GUID, for example 2781f7e7-99a8-45a0-8d55-cb37c0556b30."
  }
}

variable "location" {
  description = "Azure region for nonprod resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Resource group that holds the nonprod environment."
  type        = string
}

variable "vnet_name" {
  description = "Name of the nonprod virtual network."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space of the nonprod virtual network. It has to differ from every other environment's range, so that the networks can be peered later without renumbering."
  type        = list(string)
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for each nonprod subnet. See ../../modules/networking/README.md."
  type = object({
    aks               = list(string)
    aks_apiserver     = list(string)
    postgres          = list(string)
    private_endpoints = list(string)
  })
}

variable "tags" {
  description = "Tags applied to every nonprod resource that supports them."
  type        = map(string)
  default = {
    project     = "cronus"
    environment = "nonprod"
    managed_by  = "terraform"
  }
}

variable "acr_name" {
  description = "Name of the nonprod container registry. Globally unique, letters and digits only."
  type        = string
}

variable "acr_sku" {
  description = "Registry SKU. Private link needs Premium, so this changes if private endpoints are ever added."
  type        = string
}

variable "key_vault_name" {
  description = "Name of the nonprod key vault. Globally unique."
  type        = string
}

variable "key_vault_soft_delete_retention_days" {
  description = "Days a deleted nonprod vault or secret stays recoverable."
  type        = number
}

variable "key_vault_purge_protection_enabled" {
  description = "Whether a deleted nonprod vault is protected from being purged early. Off here so the vault name can be reused without waiting out the retention period; prod keeps it on."
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
  description = "Workload identity names, keyed by application environment and service, for example ordering_dev."
  type        = map(string)
}

variable "migration_identity_names" {
  description = "Migration identity names, keyed by the same application environment and service keys as workload_identity_names, for example ordering_dev."
  type        = map(string)
}

variable "workload_federated_credentials" {
  description = <<-EOT
    Federated identity credentials for the nonprod workloads, keyed by the credential's
    name in Microsoft Entra ID. The subject names the Kubernetes namespace and service
    account that will present the token, which cronus-gitops owns, so these strings have
    to agree with that repository.
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

variable "github_ci" {
  description = <<-EOT
    One row per application whose continuous integration publishes to the registry, keyed
    by the application. Each row states the three names that have to agree: the identity
    in Azure, the subject GitHub issues for the repository that may assume it, and the
    registry repository the images are pushed to.

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
  description = "Name of the nonprod PostgreSQL server. It is part of the FQDN, so it has to be globally unique."
  type        = string
}

variable "postgres_private_dns_zone_name" {
  description = "Name of the private DNS zone that publishes the nonprod server's address. The zone name becomes the server's FQDN, so this is the hostname the applications connect to."
  type        = string
}

variable "postgres_version" {
  description = "Major version of PostgreSQL."
  type        = string
}

variable "postgres_sku_name" {
  description = "Server SKU. Nonprod runs on the cheapest Burstable one; prod will want more."
  type        = string
}

variable "postgres_storage_mb" {
  description = "Server storage in MiB, which cannot be shrunk later."
  type        = number
}

variable "postgres_backup_retention_days" {
  description = "Days of automated backups to keep."
  type        = number
}

variable "postgres_geo_redundant_backup_enabled" {
  description = "Whether backups are replicated to the paired region."
  type        = bool
}

variable "admin_groups" {
  description = <<-EOT
    Entra ID security groups that administer something, keyed by purpose. The identities
    module creates them, and whatever they administer is handed their object id, so no
    individual account ever owns the way in to a database or a cluster. Members are
    listed explicitly rather than derived from whoever runs Terraform, so who can
    administer what is reviewed like any other change and an automated run cannot add
    itself. The key becomes the instance address in state.
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
  description = "Name of the nonprod Kubernetes cluster."
  type        = string
}

variable "aks_dns_prefix" {
  description = "Prefix for the cluster's API server DNS name. AKS appends a hash and the region."
  type        = string
}

variable "aks_kubernetes_version" {
  description = "Kubernetes minor version for nonprod, for example 1.35. AKS picks the newest patch of that minor; raising this is how the cluster is upgraded."
  type        = string
}

variable "aks_sku_tier" {
  description = "Cluster pricing tier for nonprod. Free omits the uptime SLA, which is the point of choosing it here."
  type        = string
}

variable "aks_pod_cidr" {
  description = "Address range pods are allocated from. Overlay keeps it off the virtual network, so it must not overlap the virtual network or the service range, and it cannot be changed after creation."
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

variable "aks_api_server_authorized_ip_ranges" {
  description = "Address ranges allowed to reach the API server. Keep this current: an address missing from here cannot run kubectl, and an empty list would publish the API server to the internet."
  type        = list(string)
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
  description = "Gateway API ingress for nonprod. Application Routing is enabled, and its nginx controller kept uncreated, by the module rather than from here. See ../../modules/aks/README.md."
  type = object({
    installation           = string
    app_routing_istio_mode = string
  })
}

variable "aks_key_vault_secrets_provider" {
  description = "Secrets Store CSI driver settings for nonprod. See ../../modules/aks/README.md for why the Application Routing add-on needs it. The provider parses the interval and rejects a value it cannot read, so it is not re-checked here."
  type = object({
    secret_rotation_enabled  = bool
    secret_rotation_interval = string
  })
}

variable "log_analytics_workspace_name" {
  description = "Name of the nonprod Log Analytics workspace, which holds container logs and Kubernetes events."
  type        = string
}

variable "azure_monitor_workspace_name" {
  description = "Name of the nonprod Azure Monitor workspace, which holds Prometheus metrics."
  type        = string
}

variable "log_analytics_retention_in_days" {
  description = "How long the nonprod Log Analytics workspace keeps data. See ../../modules/observability/README.md."
  type        = number
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion cap for the nonprod Log Analytics workspace, in gigabytes, or -1 for none. See ../../modules/observability/README.md."
  type        = number
}

variable "container_insights_streams" {
  description = "The streams Container Insights collects for nonprod. The module refuses the metric streams, because managed Prometheus already collects those. See ../../modules/aks/README.md."
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
  description = "Name of the nonprod Action Group that alert rules notify."
  type        = string
}

variable "alert_action_group_short_name" {
  description = "Short name of the nonprod Action Group, at most 12 characters. See ../../modules/alerting/README.md."
  type        = string
}

variable "alert_email_receivers" {
  description = <<-EOT
    Email addresses notified when a nonprod alert fires. This is the only place a recipient is
    named: the module takes a list, so changing who is told is a change to this value and
    nothing else. At least one address is required.
  EOT
  type        = list(string)
}

variable "alert_thresholds" {
  description = "Tuning for the nonprod alert rules. The module holds the defaults, which are set to avoid noise; see ../../modules/alerting/README.md before overriding one."
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
  description = "Application Insights resources for nonprod, keyed by environment and service. See ../../modules/observability/README.md."
  type        = map(string)
}
