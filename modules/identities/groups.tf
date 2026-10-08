# Security groups belong to the tenant rather than to an environment, but they are
# created here because they exist to identify people and services, and because
# whatever consumes one should receive it rather than invent it.
#
# They are security groups and not mail-enabled ones: there is no mailbox behind an
# administrator group, and mail-enabled groups bring a Microsoft 365 licence with
# them.
#
# Ownership is left to the provider's default, which is the principal running
# Terraform, so no owner can go missing from the configuration and leave the group
# unmanageable.

resource "azuread_group" "this" {
  for_each = var.security_groups

  display_name     = each.value.name
  description      = each.value.description
  security_enabled = true
  members          = each.value.members
}
