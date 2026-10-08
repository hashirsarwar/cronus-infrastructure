# Who gets told when something fires.
#
# One group for the whole environment rather than one per alert, so that adding a route later —
# a webhook, a ticketing connector, a second team — is a change in one place instead of in
# every alert. The rules themselves name this group; none of them names a recipient.

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  # Action groups are not tied to a region. The short name is what appears in an SMS and at the
  # start of a notification, which is why it is capped at twelve characters and why it names the
  # environment rather than the project.
  location = "global"

  # One receiver per address, so adding or removing a recipient is a change to a list rather
  # than to this block. Names have to be unique within the group, which the index gives them;
  # the variable refuses duplicates so the two cannot get out of step.
  dynamic "email_receiver" {
    for_each = { for index, address in var.email_receivers : index => address }

    content {
      name          = "email-${email_receiver.key + 1}"
      email_address = email_receiver.value

      # The common alert schema replaces the classic per-alert-type payload with one structure.
      # Nothing here consumes it yet, but it is the shape a future webhook or logic app would
      # be written against, and it is not something to change later once alerts are live.
      use_common_alert_schema = true
    }
  }
}
