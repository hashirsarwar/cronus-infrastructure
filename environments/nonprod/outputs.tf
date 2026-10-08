# GitOps uses these client IDs for ServiceAccount annotations; IDs identify identities, not credentials.

output "workload_identity_client_ids" {
  description = "Client ids of the nonprod workload identities, keyed by application environment and service. These are the values a ServiceAccount annotation carries."
  value       = module.identities.workload_client_ids
}

output "github_ci_identity_client_ids" {
  description = "Client ids of the GitHub CI identities, keyed by application. These are the values the AZURE_CLIENT_ID repository variable carries, and they are not secrets."
  value       = module.identities.ci_client_ids
}

output "migration_identity_client_ids" {
  description = "Client ids of the nonprod migration identities, keyed by application environment and service. These are the values the azure.workload.identity/client-id annotation on a migration job's service account carries, and they are not secrets."
  value       = module.identities.migration_client_ids
}

output "migration_identity_principal_ids" {
  description = "Entra ID object ids of the nonprod migration identities. The PostgreSQL bootstrap maps these object ids to database roles."
  value       = module.identities.migration_principal_ids
}

output "log_analytics_workspace_id" {
  description = "Resource id of the nonprod Log Analytics workspace. Container insights writes container output and Kubernetes events here, and it is what a query client is pointed at."
  value       = module.observability.log_analytics_workspace_id
}

output "azure_monitor_workspace_id" {
  description = "Resource id of the nonprod Azure Monitor workspace, which holds Prometheus metrics."
  value       = module.observability.azure_monitor_workspace_id
}

output "azure_monitor_workspace_query_endpoint" {
  description = "Prometheus query endpoint of the nonprod Azure Monitor workspace. This is the address a Grafana data source would be given; nothing is using it yet."
  value       = module.observability.azure_monitor_workspace_query_endpoint
}

# Not a value another repository needs, unlike everything above. It is the read-back of what
# Azure actually stored for the cluster's ingress profile, which is how the Gateway API
# settings are confirmed rather than assumed: a plan can say what it will send, not what came
# back.
output "aks_gateway_api_ingress_profile" {
  description = "Ingress profile Azure reports for aks-cronus-nonprod after the Gateway API settings were applied, including the managed Gateway API installation and the Application Routing Istio implementation."
  value       = module.aks.gateway_api_ingress_profile
}

output "alert_action_group_id" {
  description = "Resource id of the nonprod Action Group. Every alert rule notifies it, and anything added later that should reach the same people names it."
  value       = module.alerting.action_group_id
}

output "application_insights_connection_strings" {
  description = <<-EOT
    Connection strings for the nonprod Application Insights resources, keyed by environment and
    service. cronus-gitops puts one into each Deployment as APPLICATIONINSIGHTS_CONNECTION_STRING.

    Sensitive, so it is not printed by a plan or an apply. Read it with:

      terraform output -json application_insights_connection_strings
  EOT
  value       = module.observability.application_insights_connection_strings
  sensitive   = true
}
