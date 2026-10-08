output "source_reader_assignment_ids" {
  description = "Role assignment ids granting data-plane read of the promoter's own repository in the source registry, keyed by the promoter the assignment belongs to."
  value = {
    for label, assignment in azurerm_role_assignment.source_reader : label => assignment.id
  }
}

output "source_registry_reader_assignment_ids" {
  description = "Role assignment ids granting ARM read of the source registry, keyed by the promoter. Distinct from the source repository reader below, which grants data-plane read of one repository rather than read of the registry resource."
  value = {
    for label, assignment in azurerm_role_assignment.source_registry_reader : label => assignment.id
  }
}

output "source_read_role_definition_resource_id" {
  description = "Resource id of the role definition granting ARM read of the source registry, for inspecting the permission actually granted."
  value       = azurerm_role_definition.source_read.role_definition_resource_id
}

output "destination_importer_assignment_ids" {
  description = "Role assignment ids granting the import capability, keyed by the promoter the assignment belongs to."
  value = {
    for label, assignment in azurerm_role_assignment.destination_importer : label => assignment.id
  }
}

output "import_role_definition_resource_id" {
  description = "Resource id of the import role definition, for inspecting the permissions actually granted. It is a definition, not a grant: what is granted is decided by the assignments above."
  value       = azurerm_role_definition.import_image.role_definition_resource_id
}
