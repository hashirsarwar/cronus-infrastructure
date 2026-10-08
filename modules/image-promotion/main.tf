# Grant source image read, source ARM read and destination import together.
# Neither registry is managed here; see README.md for promotion boundaries.

locals {
  # Use only importImage/action and registries/read, avoiding the built-in importer's broad data access.
  # Repository ABAC cannot constrain importImage; legacy pull/read adds nothing in ABAC mode.
  # If Azure later requires another action, investigate the authorization failure before extending the role.
  import_actions = [
    "Microsoft.ContainerRegistry/registries/importImage/action",
    "Microsoft.ContainerRegistry/registries/read",
  ]

  # One ARM action, and the only permission in this module that is about a registry *resource* rather
  # than about the images inside it. An import names the source registry by resource id in its request
  # body, and ARM checks that the caller may read that resource before it copies anything. That check is
  # separate from the repository permissions and is what `LinkedAuthorizationFailed` is about when it
  # names a registry the caller is apparently able to read images from.
  source_read_actions = [
    "Microsoft.ContainerRegistry/registries/read",
  ]

  # The data actions of `Container Registry Repository Reader`, which is ABAC-enabled and so can be
  # narrowed. Everything the role grants is listed, because anything left out keeps its grant across
  # the whole registry.
  reader_data_actions = [
    "Microsoft.ContainerRegistry/registries/repositories/content/read",
    "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
  ]

  # The second clause of every condition: the repository the request is about is one of these.
  repository_clauses = {
    for label, promoter in var.promoters :
    label => join(" OR ", [
      for repository in promoter.repositories :
      "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase '${repository}'"
    ])
  }
}

# A role definition rather than a built-in role, because no built-in role grants the import without
# also granting read of every repository in the registry. It has no repository data actions, so it
# cannot read or write an image by itself; what an identity can do with the images it imports comes
# from the repository role it already holds on its own repository.
resource "azurerm_role_definition" "import_image" {
  name        = var.role_definition_name
  description = "Triggers an image import into this registry, and nothing else. Grants the control-plane actions the import operation uses and no repository data actions, so it cannot read or write an image on its own."
  scope       = var.role_definition_scope

  permissions {
    actions = local.import_actions
  }

  # The widest scope this role may be assigned within. What is granted is decided by the assignment
  # below, which is made against the registry and not against this scope.
  assignable_scopes = [var.role_definition_scope]
}

# Source repository data grants do not satisfy ARM's separate registries/read check.
# Without this grant, import fails with LinkedAuthorizationFailed.
# Use a custom role to grant only that action on the source registry.
resource "azurerm_role_definition" "source_read" {
  name        = var.source_read_role_definition_name
  description = "Reads this container registry's own ARM resource, and nothing inside it. An import into another registry requires the caller to be able to read the source registry, which is a control-plane permission no repository role grants."
  scope       = var.role_definition_scope

  permissions {
    actions = local.source_read_actions
  }

  assignable_scopes = [var.role_definition_scope]
}

# The assignment that puts it on the source registry, one per promoting application.
resource "azurerm_role_assignment" "source_registry_reader" {
  for_each = var.promoters

  scope              = var.source_registry_id
  role_definition_id = azurerm_role_definition.source_read.role_definition_resource_id
  principal_id       = each.value.principal_id
  principal_type     = each.value.principal_type

  lifecycle {
    precondition {
      condition     = startswith(var.source_registry_id, var.role_definition_scope)
      error_message = "source_registry_id must be inside role_definition_scope: a role definition can only be assigned within the scopes it declares itself assignable at. A source registry in another subscription needs this role definition created in that subscription instead."
    }
  }
}

# Both source grants are required: this reads image content; the ARM grant authorizes the registry reference.
# List every reader data action in the condition so none retains registry-wide access.
resource "azurerm_role_assignment" "source_reader" {
  for_each = var.promoters

  scope                = var.source_registry_id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type

  condition_version = "2.0"
  condition = format(
    "((%s) OR (%s))",
    join(" AND ", [
      for action in local.reader_data_actions : "!(ActionMatches{'${action}'})"
    ]),
    local.repository_clauses[each.key],
  )
}

# importImage is registry-wide: this identity can target any destination repository.
# The workflow omits --force to prevent overwrites; this grant does not enforce that choice.
# Source reads stay repository-scoped; see README.md for the residual capability and accepted tradeoffs.
resource "azurerm_role_assignment" "destination_importer" {
  for_each = var.promoters

  scope              = var.destination_registry_id
  role_definition_id = azurerm_role_definition.import_image.role_definition_resource_id
  principal_id       = each.value.principal_id
  principal_type     = each.value.principal_type

  lifecycle {
    precondition {
      condition     = startswith(var.destination_registry_id, var.role_definition_scope)
      error_message = "destination_registry_id must be inside role_definition_scope. A role definition can only be assigned within the scopes it declares itself assignable at, so an assignment outside it would be refused by Azure at apply time."
    }
  }
}
