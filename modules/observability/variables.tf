variable "resource_group_name" {
  description = "Resource group that both workspaces are created in."
  type        = string
}

variable "location" {
  description = "Azure region of both workspaces. Has to match the region of the resource group, and should match the cluster: Container Insights and the Prometheus add-on both ingest from the cluster's region."
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace that Container Insights writes logs and Kubernetes events to. It does not have to be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace names must be 4 to 63 characters, letters, digits and hyphens only."
  }
}

variable "azure_monitor_workspace_name" {
  description = "Name of the Azure Monitor workspace that holds Prometheus metrics. It does not have to be globally unique, and Azure allows letters, digits and hyphens."
  type        = string

  # Azure's constraint on the length is not published, so this checks the shape rather than
  # a bound it cannot be trusted to have. The provider checks no more either: it requires
  # the name to be non-empty and leaves everything else to the service.
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.azure_monitor_workspace_name))
    error_message = "Azure Monitor workspace names may contain letters, digits and hyphens only."
  }
}

variable "log_analytics_retention_in_days" {
  description = "How long the Log Analytics workspace keeps data. 30 is the shortest period included in the price; anything longer is charged by the gigabyte. The minimum the service accepts is 30, and the maximum without a commitment tier is 730."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "log_analytics_retention_in_days must be between 30 and 730."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = <<-EOT
    Daily ingestion cap for the Log Analytics workspace, in gigabytes. Once it is reached,
    ingestion stops until the next day, which bounds the workspace's cost. It is not a
    sampling setting: data is dropped, not thinned, and the drop is visible in the data.

    -1 removes the cap. The service's smallest meaningful cap is 0.023 GB. Note that this
    bounds the Log Analytics workspace alone; Prometheus metrics are billed through the
    Azure Monitor workspace and are not covered by it.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.log_analytics_daily_quota_gb == -1 || var.log_analytics_daily_quota_gb >= 0.023
    error_message = "log_analytics_daily_quota_gb must be -1 for no cap, or at least 0.023."
  }
}

variable "tags" {
  description = "Tags applied to both workspaces."
  type        = map(string)
  default     = {}
}

variable "application_insights" {
  description = <<-EOT
    Application Insights resources to create, keyed by the name the connection string output uses.

    One entry per service per environment. The key is what the connection string map is keyed by,
    so it is worth making it readable: an environment and a service rather than a number, so the
    value an operator copies out of `terraform output` is identifiable without a lookup.

    The values are the resource names, which belong to the environment rather than to this module
    in the same way the workspace names do.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name in values(var.application_insights) : can(regex("^[a-zA-Z0-9-]{1,255}$", name))
    ])
    error_message = "Application Insights names may contain letters, digits and hyphens, up to 255 characters."
  }

  validation {
    condition     = length(var.application_insights) == length(distinct(values(var.application_insights)))
    error_message = "Two Application Insights entries share a name. Resource names have to be unique within the resource group."
  }
}
