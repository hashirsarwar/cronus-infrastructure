# ABAC registries require Repository Reader; legacy AcrPull is not honoured.
# These kubelet grants cover every repository because cluster nodes pull all workloads.

locals {
  # Every data action Container Registry Repository Writer grants, taken from the role
  # definition rather than from the documentation. The ABAC condition has to name each one
  # it restricts, so this list is what makes the narrowing complete.
  writer_data_actions = [
    "Microsoft.ContainerRegistry/registries/repositories/content/read",
    "Microsoft.ContainerRegistry/registries/repositories/content/write",
    "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
    "Microsoft.ContainerRegistry/registries/repositories/metadata/write",
  ]
}

resource "azurerm_role_assignment" "repository_reader" {
  for_each = var.repository_readers

  scope                = azurerm_container_registry.this.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}

# Restrict every writer data action to the named repositories; omitted actions remain registry-wide.
# Assignments stay at registry scope, with repository narrowing supplied by the ABAC condition.
resource "azurerm_role_assignment" "repository_writer" {
  for_each = var.repository_writers

  scope                = azurerm_container_registry.this.id
  role_definition_name = "Container Registry Repository Writer"
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type

  condition_version = "2.0"
  condition = format(
    "((%s) OR (%s))",
    join(" AND ", [
      for action in local.writer_data_actions : "!(ActionMatches{'${action}'})"
    ]),
    join(" OR ", [
      for repository in each.value.repositories :
      "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase '${repository}'"
    ]),
  )
}
