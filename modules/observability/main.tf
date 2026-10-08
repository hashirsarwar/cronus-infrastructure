# The stores the platform's telemetry lands in.
#
# Two workspaces, because they hold different things and neither can hold the other's data.
# Metrics go to an Azure Monitor workspace, which is the store behind Azure Monitor managed
# service for Prometheus. Logs and Kubernetes events go to a Log Analytics workspace, which is
# what Container Insights writes to. A cluster using both therefore needs both: a Log Analytics
# workspace on its own cannot serve Prometheus, and an Azure Monitor workspace holds no logs.
#
# Application Insights sits in front of the Log Analytics workspace rather than beside it. Each
# service's traces, metrics and logs are written to its own Application Insights resource, and
# that resource stores them in the workspace above, so there is one place to query from and one
# retention and one daily cap governing all of it.

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # PerGB2018 is the pay-as-you-go tier, and the only one that fits nonprod. The commitment
  # tiers buy a lower per-gigabyte rate by paying for capacity whether or not it is used,
  # which suits a large steady volume rather than a small irregular one.
  sku = "PerGB2018"

  # 30 days is the retention included in the price. Anything longer is charged by volume,
  # so it stays at the default until there is a reason to keep data for longer.
  retention_in_days = var.log_analytics_retention_in_days

  # A daily cap, which is the one control that stops a noisy cluster becoming an unbounded
  # bill. Ingestion stops for the rest of the day once the cap is reached, so this is a
  # spending limit rather than a sampling setting: the gap it leaves is visible in the data,
  # and the cap is raised by changing one value.
  daily_quota_gb = var.log_analytics_daily_quota_gb
}

resource "azurerm_monitor_workspace" "this" {
  name                = var.azure_monitor_workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # No private link yet, so the workspace is reachable over the public network by anything
  # holding a role on it. That is the same posture as the registry and the key vault, and
  # what a private endpoint would tighten together with them.
  public_network_access_enabled = true
}

# Application Insights, one resource per service per environment.
#
# Workspace-based rather than classic: the data lands in the Log Analytics workspace above rather
# than in a storage account Azure manages inside the resource, which is what allows a query to
# join a trace to a container log line. Azure defaults new resources to workspace-based, so
# naming the workspace states the intent rather than relying on the default.
#
# One per service rather than one shared, because the connection string is what decides where a
# service writes and the cloud role name groups by service anyway. Separate resources mean one
# service's telemetry can be capped, queried or deleted without touching the other's, and a
# service's ingestion is attributable to it when the bill is read.
resource "azurerm_application_insights" "this" {
  for_each = var.application_insights

  name                = each.value
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # "web" is the Application Insights value for a web application, which covers both the ASP.NET
  # services and the browser telemetry the front end sends. Azure treats an unrecognised value as
  # web anyway, so this is stated rather than inferred.
  application_type = "web"

  # The Log Analytics workspace the data is stored in. Not set means classic, with the data in a
  # store Azure owns and manages, which cannot be queried alongside container logs and cannot be
  # made to respect the workspace's daily cap.
  workspace_id = azurerm_log_analytics_workspace.this.id

  # Stated rather than left to the provider's own default of 90, which would have this resource
  # advertise a longer retention than it keeps: for a workspace-based resource the data lives in
  # the workspace and it is the workspace's retention that actually applies. Mirroring the
  # workspace's value means the two agree, and the resource cannot be read as keeping data for
  # longer than the bill reflects.
  retention_in_days = var.log_analytics_retention_in_days

  # No daily_data_cap_in_gb. The cap that applies to a workspace-based resource is the workspace's
  # own daily_quota_gb, set above; a second cap here would be a limit that does not govern anything
  # and a second place to look when ingestion stops. See the module README.
}
