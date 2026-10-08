output "log_analytics_workspace_id" {
  description = "Resource id of the Log Analytics workspace. The cluster's Container Insights add-on takes this, and so does the data collection rule that carries container logs and Kubernetes events into it."
  value       = azurerm_log_analytics_workspace.this.id
}

output "azure_monitor_workspace_id" {
  description = "Resource id of the Azure Monitor workspace. The data collection rule behind managed Prometheus names it as the destination its metrics are written to."
  value       = azurerm_monitor_workspace.this.id
}

output "azure_monitor_workspace_query_endpoint" {
  description = "Prometheus query endpoint of the Azure Monitor workspace. This is the address a Grafana data source or a query client is pointed at; nothing in this configuration uses it yet."
  value       = azurerm_monitor_workspace.this.query_endpoint
}

output "azure_monitor_workspace_default_data_collection_rule_id" {
  description = <<-EOT
    The data collection rule Azure created alongside the workspace, in its own managed
    resource group. Nothing is associated with it: the cluster is pointed at a rule this
    configuration owns instead, so that what is collected is stated here rather than
    inferred. It is exported so that the difference between the two is visible.
  EOT
  value       = azurerm_monitor_workspace.this.default_data_collection_rule_id
}

output "application_insights_ids" {
  description = "Resource ids of the Application Insights resources, keyed as the input was. Useful for a role assignment or a query, neither of which is needed yet."
  value       = { for key, resource in azurerm_application_insights.this : key => resource.id }
}

output "application_insights_connection_strings" {
  description = <<-EOT
    Connection strings, keyed as the input was, for the services to be given as
    APPLICATIONINSIGHTS_CONNECTION_STRING in the environment they run in.

    Marked sensitive so that a plan or an apply in a shared log does not print them. A connection
    string authorises ingestion rather than reading, so it is not a credential in the sense of
    granting access to data, but it is still configuration and there is no reason to print it.
    Read one with:

      terraform output -json application_insights_connection_strings | jq -r '.ordering_dev'
  EOT
  value       = { for key, resource in azurerm_application_insights.this : key => resource.connection_string }
  sensitive   = true
}
