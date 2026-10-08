output "aks_ids" {
  description = "Resource ids of the cluster identities, keyed by controlplane and kubelet."
  value       = { for purpose, identity in azurerm_user_assigned_identity.aks : purpose => identity.id }
}

output "aks_principal_ids" {
  description = "Entra ID object ids of the cluster identities. Role assignments, such as AcrPull for the kubelet identity, are made against these."
  value       = { for purpose, identity in azurerm_user_assigned_identity.aks : purpose => identity.principal_id }
}

output "aks_client_ids" {
  description = "Client ids of the cluster identities."
  value       = { for purpose, identity in azurerm_user_assigned_identity.aks : purpose => identity.client_id }
}

output "workload_ids" {
  description = "Resource ids of the workload identities, keyed by application environment and service."
  value       = { for purpose, identity in azurerm_user_assigned_identity.workload : purpose => identity.id }
}

output "workload_principal_ids" {
  description = "Entra ID object ids of the workload identities. Role assignments, such as reading the key vault, are made against these."
  value       = { for purpose, identity in azurerm_user_assigned_identity.workload : purpose => identity.principal_id }
}

output "security_group_object_ids" {
  description = "Entra ID object ids of the security groups, keyed by purpose. Anything administered through a group, such as the PostgreSQL server, is configured with these."
  value       = { for purpose, group in azuread_group.this : purpose => group.object_id }
}

output "ci_ids" {
  description = "Resource ids of the CI identities, keyed by application."
  value       = { for app, identity in azurerm_user_assigned_identity.ci : app => identity.id }
}

output "ci_principal_ids" {
  description = "Entra ID object ids of the CI identities. Role assignments, such as writing to the registry, are made against these."
  value       = { for app, identity in azurerm_user_assigned_identity.ci : app => identity.principal_id }
}

output "ci_client_ids" {
  description = "Client ids of the CI identities, which is what a workflow presents when it signs in."
  value       = { for app, identity in azurerm_user_assigned_identity.ci : app => identity.client_id }
}

output "workload_client_ids" {
  description = "Client ids of the workload identities, for workload identity annotations and, later, federated credentials."
  value       = { for purpose, identity in azurerm_user_assigned_identity.workload : purpose => identity.client_id }
}

output "migration_ids" {
  description = "Resource ids of the database migration identities, keyed by application environment and service."
  value       = { for purpose, identity in azurerm_user_assigned_identity.migrations : purpose => identity.id }
}

output "migration_principal_ids" {
  description = "Entra ID object ids of the database migration identities. The PostgreSQL bootstrap maps these to database roles."
  value       = { for purpose, identity in azurerm_user_assigned_identity.migrations : purpose => identity.principal_id }
}

output "migration_client_ids" {
  description = "Client ids of the database migration identities, which the annotation on the migration job's service account carries."
  value       = { for purpose, identity in azurerm_user_assigned_identity.migrations : purpose => identity.client_id }
}
