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
}

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
  tags                    = var.tags
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

  # Each application's CI identity may push to its own repository and no other.
  repository_writers = local.repository_writers
}

module "key_vault" {
  source = "../../modules/key-vault"

  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  name                       = var.key_vault_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  tags                       = var.tags
}

module "observability" {
  source = "../../modules/observability"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  log_analytics_workspace_name = var.log_analytics_workspace_name
  azure_monitor_workspace_name = var.azure_monitor_workspace_name

  log_analytics_retention_in_days = var.log_analytics_retention_in_days
  log_analytics_daily_quota_gb    = var.log_analytics_daily_quota_gb

  # One per service per environment, so a service's traces and logs land in their own resource and
  # its ingestion can be read, capped or deleted on its own. The key is what the connection string
  # output is keyed by, which is what a deployment reads to find the value for its service.
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
  sku_tier            = var.aks_sku_tier
  tenant_id           = data.azurerm_client_config.current.tenant_id

  subnet_id            = module.networking.aks_subnet_id
  api_server_subnet_id = module.networking.aks_apiserver_subnet_id

  pod_cidr                        = var.aks_pod_cidr
  service_cidr                    = var.aks_service_cidr
  dns_service_ip                  = var.aks_dns_service_ip
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
  # unused, so this grant is what makes the cluster administrable.
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

  name_prefix = "cronus-nonprod"

  action_group_name       = var.alert_action_group_name
  action_group_short_name = var.alert_action_group_short_name
  email_receivers         = var.alert_email_receivers

  thresholds = var.alert_thresholds

  tags = var.tags
}
