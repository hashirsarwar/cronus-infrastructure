# Keep cluster identities per Terraform environment and workload identities per application environment.
# Nonprod carries dev/staging; prod carries production. Names also bind to PostgreSQL roles and GitOps federation.

resource "azurerm_user_assigned_identity" "aks" {
  for_each = var.aks_identity_names

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each = var.workload_identity_names

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Paired with the workload identity of the same application environment, and federated the
# same way. What separates them is what they are granted: the PostgreSQL role for this
# identity may create and alter schema objects, and the role for the pod may not.
resource "azurerm_user_assigned_identity" "migrations" {
  for_each = var.migration_identity_names

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# CI identities are assumed from outside the cluster, by a repository rather than by a
# pod, so they are kept apart from the workload identities that pods use.
resource "azurerm_user_assigned_identity" "ci" {
  for_each = var.ci_identity_names

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
