data "azurerm_client_config" "current" {}

locals {
  # Derive CI identity, federated subject and registry grants together so application names cannot drift.
  ci_identity_names = {
    for app, ci in var.github_ci : app => ci.identity_name
  }

  github_federated_credentials = {
    for app, ci in var.github_ci : "github-${app}" => {
      identity = app
      subject  = ci.subject
    }
  }

  # The key is the label the assignment is addressed by in state, not the application name,
  # so that an assignment reads as belonging to the application's CI identity.
  repository_writers = {
    for app, ci in var.github_ci : "${app}_ci" => {
      principal_id   = module.identities.ci_principal_ids[app]
      principal_type = "ServicePrincipal"
      repositories   = [ci.acr_repository]
    }
  }

  # The registry a production image is promoted from, as an id built from the parts in
  # terraform.tfvars. Production holds a grant on that registry and does not manage it.
  promotion_source_registry_id = join("/", [
    "/subscriptions/${var.promotion_source.subscription_id}",
    "resourceGroups/${var.promotion_source.resource_group_name}",
    "providers/Microsoft.ContainerRegistry/registries/${var.promotion_source.registry_name}",
  ])

  # The same identities that publish to production's registry, and the same repository each of
  # them owns. Promotion is the second half of the same job, so it is the same principal rather
  # than a new one: a release that may publish an image into production may also copy the one it
  # published. What it may copy is stated once, here, and read by both grants.
  promoters = {
    for app, ci in var.github_ci : "${app}_ci" => {
      principal_id   = module.identities.ci_principal_ids[app]
      principal_type = "ServicePrincipal"
      repositories   = [ci.acr_repository]
    }
  }
}

# Keep production resources separate; promotion adds only source-registry grants in nonprod.
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  vnet_name               = var.vnet_name
  address_space           = var.vnet_address_space
  subnet_address_prefixes = var.subnet_address_prefixes

  # Keep NSG ports explicit per environment; the Gateway alone does not authorize public traffic.
  # Production terraform.tfvars admits HTTP on port 80; the example keeps ingress closed.
  public_ingress = var.public_ingress

  tags = var.tags
}

module "postgres" {
  source = "../../modules/postgres"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name                = var.postgres_server_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  delegated_subnet_id = module.networking.postgres_subnet_id
  virtual_network_id  = module.networking.vnet_id

  private_dns_zone_name = var.postgres_private_dns_zone_name

  # Use an explicitly populated admin group so membership can change without altering the server.
  # Password authentication is disabled; production and nonprod use separate groups.
  entra_administrator = {
    object_id      = module.identities.security_group_object_ids["postgres_admins"]
    principal_name = var.admin_groups["postgres_admins"].name
    principal_type = "Group"
  }

  database_names = var.postgres_database_names

  server_version               = var.postgres_version
  sku_name                     = var.postgres_sku_name
  storage_mb                   = var.postgres_storage_mb
  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = var.postgres_geo_redundant_backup_enabled

  # The zone Azure placed the server in. Stated so that a rebuild lands where this one is,
  # and ignored on every plan afterwards so it is never treated as drift.
  zone = var.postgres_zone

  # A standby in a second zone, promoted automatically. The alternative is a single server
  # whose zone failing takes the database with it, and this is the one environment where
  # that is not an acceptable answer.
  high_availability = var.postgres_high_availability

  tags = var.tags
}

module "acr" {
  source = "../../modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name                = var.acr_name
  sku                 = var.acr_sku
  tags                = var.tags

  # The cluster's kubelet identity pulls images. Taken from the identities module rather
  # than from the cluster, so the grant does not have to wait for the cluster to exist.
  repository_readers = {
    kubelet = {
      principal_id   = module.identities.aks_principal_ids["kubelet"]
      principal_type = "ServicePrincipal"
    }
  }

  # Each application's CI identity may push to its own repository and no other. These are
  # production's own identities, writing to production's own registry, so a repository that
  # can publish an image into production is a repository that has been granted that here.
  repository_writers = local.repository_writers
}

# Production owns both promotion grants so nonprod need not reference production identities.
# The only cross-environment writes are role assignments on the source registry.
# See modules/image-promotion/README.md for permission limits.
module "image_promotion" {
  source = "../../modules/image-promotion"

  source_registry_id      = local.promotion_source_registry_id
  destination_registry_id = module.acr.id

  # The role definition is created in production's subscription, and the assignment that grants it
  # is made against the registry inside it.
  role_definition_scope = "/subscriptions/${var.subscription_id}"

  # Two role definitions, because promotion needs two different kinds of permission: read of the source
  # registry's own ARM resource, and the ability to trigger the copy into this registry. Neither implies
  # the other and the source one is not a repository permission, which is why it is a role definition of
  # its own rather than an extra action somewhere.
  role_definition_name             = var.import_role_definition_name
  source_read_role_definition_name = var.source_read_role_definition_name

  promoters = local.promoters
}

module "key_vault" {
  source = "../../modules/key-vault"

  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  name                       = var.key_vault_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  # On here, and off in nonprod. Purge protection is what stops a deleted vault — and with
  # it every secret in it — being destroyed before its retention period has run out, which is
  # the accident it exists to prevent. Nonprod turns it off so the name can be reused during
  # a rebuild; production has no rebuilds that are worth that risk.
  purge_protection_enabled = var.key_vault_purge_protection_enabled

  tags = var.tags
}

module "observability" {
  source = "../../modules/observability"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  log_analytics_workspace_name = var.log_analytics_workspace_name
  azure_monitor_workspace_name = var.azure_monitor_workspace_name

  # Longer retention and a higher ingestion cap than nonprod, both deliberate. See
  # terraform.tfvars: production telemetry is the record of what happened, and it is not
  # stored beside nonprod's or governed by nonprod's limits.
  log_analytics_retention_in_days = var.log_analytics_retention_in_days
  log_analytics_daily_quota_gb    = var.log_analytics_daily_quota_gb

  # One per service, keyed by the environment and service the deployment looks the
  # connection string up by. Each stores into the production workspace above, so production
  # telemetry cannot land in nonprod's.
  application_insights = var.application_insights

  tags = var.tags
}

module "identities" {
  source = "../../modules/identities"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  aks_identity_names      = var.aks_identity_names
  workload_identity_names = var.workload_identity_names
  ci_identity_names       = local.ci_identity_names
  security_groups         = var.admin_groups

  # A migration identity sits beside the workload identity of the same application
  # environment and is federated from a different service account, because what it is
  # granted in PostgreSQL is the one thing the application's own role may not have.
  migration_identity_names = var.migration_identity_names

  # The cluster needs its identities; federated credentials need its issuer.
  # These module references have no value-level cycle, so Terraform can order them.
  oidc_issuer_url                 = module.aks.oidc_issuer_url
  federated_credentials           = var.workload_federated_credentials
  migration_federated_credentials = var.migration_federated_credentials

  # GitHub issues its own tokens, so these credentials do not involve the cluster at all.
  github_federated_credentials = local.github_federated_credentials

  tags = var.tags
}

module "aks" {
  source = "../../modules/aks"

  name                = var.aks_cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = var.aks_dns_prefix
  kubernetes_version  = var.aks_kubernetes_version

  # Standard, unlike nonprod's Free. The tier buys the financially backed uptime SLA on the
  # control plane, which is the difference between a cluster that is expected to be up and
  # one that is expected to be rebuilt.
  sku_tier = var.aks_sku_tier

  tenant_id = data.azurerm_client_config.current.tenant_id

  subnet_id            = module.networking.aks_subnet_id
  api_server_subnet_id = module.networking.aks_apiserver_subnet_id

  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip

  # Keep the API server private from creation; authorized public IP ranges must remain empty.
  private_cluster_enabled = var.aks_private_cluster_enabled
  private_dns_zone_id     = var.aks_private_dns_zone_id

  # Kept required beside the private flag so that the two cannot be set to a combination
  # Azure refuses, and so that the choice is visible in the tfvars rather than implied.
  api_server_authorized_ip_ranges = var.aks_api_server_authorized_ip_ranges

  control_plane_identity = {
    id           = module.identities.aks_ids["controlplane"]
    principal_id = module.identities.aks_principal_ids["controlplane"]
  }

  kubelet_identity = {
    id        = module.identities.aks_ids["kubelet"]
    client_id = module.identities.aks_client_ids["kubelet"]
    object_id = module.identities.aks_principal_ids["kubelet"]
  }

  # Local accounts are disabled and the cluster's own admin group setting is deliberately
  # unused, so this grant is what makes the cluster administrable. On a private cluster the
  # module adds a second role to the same groups, because reaching the API server at all
  # needs a permission cluster-admin does not carry.
  cluster_admin_groups = {
    aks_admins = module.identities.security_group_object_ids["aks_admins"]
  }

  system_node_pool = var.aks_system_node_pool
  user_node_pools  = var.aks_user_node_pools

  gateway_api = var.aks_gateway_api

  key_vault_secrets_provider = var.aks_key_vault_secrets_provider

  # The cluster writes to both workspaces, so they are named here rather than inside the
  # module. The data collection rules that carry the data across live in the module, beside
  # the add-ons they serve.
  monitoring = {
    log_analytics_workspace_id   = module.observability.log_analytics_workspace_id
    azure_monitor_workspace_id   = module.observability.azure_monitor_workspace_id
    container_insights_streams   = var.container_insights_streams
    metric_annotations_allowlist = var.metric_annotations_allowlist
    metric_labels_allowlist      = var.metric_labels_allowlist
  }

  tags = var.tags
}

module "alerting" {
  source = "../../modules/alerting"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # The alerts describe this cluster and are evaluated against this workspace, so both are
  # scopes on every rule group rather than one or the other. The workspace is what holds the
  # metrics the expressions read; the cluster is what the alert is about.
  cluster_id                 = module.aks.id
  cluster_name               = module.aks.name
  azure_monitor_workspace_id = module.observability.azure_monitor_workspace_id

  name_prefix = "cronus-prod"

  # A group of its own rather than nonprod's, so who hears about production is a separate
  # decision from who hears about nonprod, and silencing one does not silence the other.
  action_group_name       = var.alert_action_group_name
  action_group_short_name = var.alert_action_group_short_name
  email_receivers         = var.alert_email_receivers

  # Set here rather than inherited from the module's defaults, which are tuned to stay quiet
  # on a development cluster. See terraform.tfvars.
  thresholds = var.alert_thresholds

  tags = var.tags
}
