# Cilium requires Linux pools; Windows nodes cannot be added to this cluster.
# The environment selects Free or Standard tier.

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  # Keep node addresses on the subnet and allocate pods from the separate overlay range.
  # Azure couples the Cilium dataplane to azure networking and cilium policy; use no second policy engine.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard"

    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  # Create control-plane and kubelet identities separately so they outlive cluster replacement and need no client secret.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity.id]
  }

  kubelet_identity {
    client_id                 = var.kubelet_identity.client_id
    object_id                 = var.kubelet_identity.object_id
    user_assigned_identity_id = var.kubelet_identity.id
  }

  # Use cluster-scoped Azure RBAC grants instead of AKS admin_group_object_ids, which bypass that authorization path.
  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  # OIDC issuer and workload identity together are what let a Kubernetes service
  # account exchange its own token for an Entra ID token. The issuer has to exist
  # before any federated identity credential can name it.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Mount vault objects through CSI and refresh rotated values without restarting pods.
  # The add-on identity gets no vault grants here; certificate and vault authorization belong to TLS setup.
  key_vault_secrets_provider {
    secret_rotation_enabled  = var.key_vault_secrets_provider.secret_rotation_enabled
    secret_rotation_interval = var.key_vault_secrets_provider.secret_rotation_interval
  }

  # The block enables Application Routing; gateway_api.tf supplies its unsupported Gateway API properties.
  # Use the required empty DNS list until DNS is configured; None avoids a second nginx ingress/load balancer.
  # None prevents controller creation but does not delete an existing controller.
  web_app_routing {
    dns_zone_ids             = []
    default_nginx_controller = "None"
  }

  # Use managed identity for log/event collection so no workspace shared key is stored.
  # monitoring.tf defines the streams and destinations; this block enables their agent.
  oms_agent {
    log_analytics_workspace_id      = var.monitoring.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  # This block enables scraping; monitoring.tf routes the metrics to their workspace.
  # Keep annotation/label allowlists unset unless queries need them, since each combination adds billable series.
  monitor_metrics {
    annotations_allowed = var.monitoring.metric_annotations_allowlist
    labels_allowed      = var.monitoring.metric_labels_allowlist
  }

  # There is no local admin account with a certificate to hand around. Every caller
  # authenticates through Entra ID, so revoking access is a directory change.
  local_account_disabled = true

  # VNet integration keeps node-to-API traffic private independently of the API's public/private setting.
  # Authorized public ranges apply only to public clusters; private clusters use their own DNS zone.
  api_server_access_profile {
    subnet_id                           = var.api_server_subnet_id
    virtual_network_integration_enabled = true
    authorized_ip_ranges                = var.private_cluster_enabled ? null : var.api_server_authorized_ip_ranges
  }

  # Keep private API endpoints and their DNS records unpublished on the public network.
  private_cluster_enabled = var.private_cluster_enabled
  private_dns_zone_id     = var.private_dns_zone_id


  default_node_pool {
    name                 = var.system_node_pool.name
    vm_size              = var.system_node_pool.vm_size
    auto_scaling_enabled = true
    min_count            = var.system_node_pool.min_count
    max_count            = var.system_node_pool.max_count
    zones                = var.system_node_pool.zones
    vnet_subnet_id       = var.subnet_id

    # Apply CriticalAddonsOnly so application pods cannot consume the system pool.
    # The system label alone is only a preference; applications need a user pool.
    only_critical_addons_enabled = true

    # Declare AKS's reported surge settings to avoid perpetual plans that remove them.
    # Review surge capacity before changing this value.
    upgrade_settings {
      max_surge = "10%"
    }

    # max_pods and the OS image are left to AKS. Azure CNI Overlay defaults to 250 pods
    # per node, which is comfortably above the 30 a system pool must support.
  }

  # Keep provisioning Manual so AKS cannot add undeclared node pools; the provider requires this block.
  node_provisioning_profile {
    mode = "Manual"
  }

  # Wait for both subnet grants: external node/API subnets require permissions Azure does not create automatically.
  # Creating the cluster first can fail provisioning.
  depends_on = [
    azurerm_role_assignment.control_plane_subnet_join,
    azurerm_role_assignment.control_plane_apiserver_subnet_join,
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = each.value.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.vm_size
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  zones                 = each.value.zones
  vnet_subnet_id        = var.subnet_id

  node_labels = each.value.node_labels
  node_taints = each.value.node_taints

  # Declared for the same reason as the system pool's: AKS reports these settings whether
  # or not they were requested, so the block has to be stated or the plan never settles.
  # Exactly one of max_surge and max_unavailable may be set.
  upgrade_settings {
    max_surge = "10%"
  }

  # No orchestrator_version: the pools follow the cluster's version, which keeps a
  # control plane upgrade from leaving pools behind on an older minor.
}



# Required because the kubelet identity sits outside the node resource group, which is
# what lets the control plane hand that identity to the nodes.
resource "azurerm_role_assignment" "control_plane_managed_identity_operator" {
  scope                = var.kubelet_identity.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.control_plane_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# Grant only the external node subnet actions needed to join it, rather than virtual-network-wide access.
resource "azurerm_role_assignment" "control_plane_subnet_join" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = var.control_plane_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# VNet-integrated API servers need a separate subnet grant; omitting it fails provisioning.
resource "azurerm_role_assignment" "control_plane_apiserver_subnet_join" {
  scope                = var.api_server_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = var.control_plane_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# Scope Azure RBAC administrator access to this cluster so group membership changes control access.
resource "azurerm_role_assignment" "cluster_admin" {
  for_each = var.cluster_admin_groups

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
  principal_type       = "Group"
}

# Private-cluster operators need runcommand/action and commandResults/read beyond Kubernetes RBAC admin.
# Local accounts remain disabled, so the role's admin-credential permission cannot yield a kubeconfig.
# Use this for bootstrap/recovery, not routine reconciliation; run-command scheduling and output limits apply.
resource "azurerm_role_assignment" "cluster_admin_run_command" {
  for_each = var.private_cluster_enabled ? var.cluster_admin_groups : {}

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = each.value
  principal_type       = "Group"
}
