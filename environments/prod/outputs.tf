# GitOps uses these client IDs for ServiceAccount annotations; IDs identify identities, not credentials.

output "workload_identity_client_ids" {
  description = "Client ids of the production workload identities, keyed by application environment and service. These are the values a ServiceAccount annotation carries."
  value       = module.identities.workload_client_ids
}

output "github_ci_identity_client_ids" {
  description = "Client ids of the production GitHub CI identities, keyed by application. These are the values the production publishing workflow's AZURE_CLIENT_ID carries, and they are not secrets. They are not the same identities nonprod's workflows use."
  value       = module.identities.ci_client_ids
}

output "migration_identity_client_ids" {
  description = "Client ids of the production migration identities, keyed by application environment and service. These are the values the azure.workload.identity/client-id annotation on a migration job's service account carries, and they are not secrets."
  value       = module.identities.migration_client_ids
}

output "migration_identity_principal_ids" {
  description = "Entra ID object ids of the production migration identities. The PostgreSQL bootstrap maps these object ids to database roles."
  value       = module.identities.migration_principal_ids
}

# The read-backs rather than a restatement of the values. What was asked for and what Azure
# created are two different things, and only the second is the environment; a plan can only
# show the first.

output "postgres_server_fqdn" {
  description = "Hostname the production applications connect to. It resolves to a private address from inside the production virtual network and nowhere else, so this is a value for a connection string and not an address anything outside can use."
  value       = module.postgres.fqdn
}

output "postgres_server_zone" {
  description = "The availability zone the production server actually occupies, read back from Azure. Production states the zone it wants at creation, so this is what to compare that against — and after a failover it is the only accurate answer, because the two zones swap."
  value       = module.postgres.zone
}

output "postgres_high_availability_mode" {
  description = "High availability mode the production server actually has. This is the read-back that confirms the standby exists rather than that the request was made."
  value       = module.postgres.high_availability_mode
}

output "postgres_database_names" {
  description = "Production databases, keyed by application environment and service. These are the names the bootstrapped roles have CONNECT on and nothing else does."
  value       = module.postgres.database_names
}

output "aks_cluster_fqdn" {
  description = "The API server address Azure reports for the production cluster. On a private cluster this is the name that resolves inside the private DNS zone AKS manages and nowhere else, which is why administration goes through the Azure control plane rather than through kubectl."
  value       = module.aks.fqdn
}

output "aks_private_fqdn" {
  description = "The API server's address inside the production virtual network."
  value       = module.aks.private_fqdn
}

output "aks_node_resource_group" {
  description = "Resource group AKS created for the production nodes, disks and load balancers. Separate from the environment's own resource group and managed by AKS."
  value       = module.aks.node_resource_group
}

output "log_analytics_workspace_id" {
  description = "Resource id of the production Log Analytics workspace. Container Insights writes container output and Kubernetes events here, and production Application Insights stores its traces here."
  value       = module.observability.log_analytics_workspace_id
}

output "azure_monitor_workspace_id" {
  description = "Resource id of the production Azure Monitor workspace, which holds Prometheus metrics."
  value       = module.observability.azure_monitor_workspace_id
}

output "azure_monitor_workspace_query_endpoint" {
  description = "Prometheus query endpoint of the production Azure Monitor workspace. This is the address a Grafana data source would be given; nothing is using it yet."
  value       = module.observability.azure_monitor_workspace_query_endpoint
}

output "aks_gateway_api_ingress_profile" {
  description = "Ingress profile Azure reports for aks-cronus-prod after the Gateway API settings were applied, including the managed Gateway API installation and the Application Routing Istio implementation. The cluster is ready to serve a Gateway; none exists yet."
  value       = module.aks.gateway_api_ingress_profile
}

output "alert_action_group_id" {
  description = "Resource id of the production Action Group. Every production alert rule notifies it, and anything added later that should reach the same people names it."
  value       = module.alerting.action_group_id
}

output "promotion_configuration" {
  description = <<-EOT
    Everything an application's production promotion workflow needs, keyed by application and
    then by the name of the repository variable that carries it. It is an output rather than a
    paragraph in a README because the pipeline's configuration and the grants that make it work
    have to agree, and two lists maintained separately do not stay agreed.

    Each application is separate because each one authenticates as its own identity, with its own
    subject and its own single repository in each registry. The registry id and the destination
    resource group are the same for all three and are repeated so that setting one repository up
    is reading one row.

    None of it is a secret: a resource id and a client id identify things, they do not
    authenticate as anything.

      terraform output -json promotion_configuration
  EOT
  value = {
    for app, ci in var.github_ci : app => {
      AZURE_CLIENT_ID_PROD                 = module.identities.ci_client_ids[app]
      AZURE_FEDERATED_SUBJECT_PROD         = ci.subject
      PROMOTION_SOURCE_REGISTRY_ID         = local.promotion_source_registry_id
      PROMOTION_DESTINATION_RESOURCE_GROUP = azurerm_resource_group.main.name
    }
  }
}

output "application_insights_connection_strings" {
  description = <<-EOT
    Connection strings for the production Application Insights resources, keyed by environment and
    service. cronus-gitops puts one into each Deployment as APPLICATIONINSIGHTS_CONNECTION_STRING.

    These are not nonprod's, and the resources behind them are not nonprod's: a production
    service that was given the wrong one would send production telemetry into the nonprod
    workspace, which is the mistake this per-environment value exists to make impossible to
    stumble into.

    Sensitive, so it is not printed by a plan or an apply. Read it with:

      terraform output -json application_insights_connection_strings
  EOT
  value       = module.observability.application_insights_connection_strings
  sensitive   = true
}
