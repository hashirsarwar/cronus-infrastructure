variable "resource_group_name" {
  description = "Resource group that holds the Action Group and the alert rule groups."
  type        = string
}

variable "location" {
  description = "Azure region of the alert rule groups. Has to match the region of the resource group."
  type        = string
}

variable "cluster_id" {
  description = "Resource id of the cluster the alerts describe. It is one of the two scopes on every rule group, and it is what ties a firing alert back to the resource it came from."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerService/managedClusters/[^/]+$", var.cluster_id))
    error_message = "cluster_id must be the resource id of an AKS cluster."
  }
}

variable "cluster_name" {
  description = "Name of the cluster. Only used in the rule groups' descriptions, which is what an operator reads in the portal."
  type        = string
}

variable "azure_monitor_workspace_id" {
  description = "Resource id of the Azure Monitor workspace the Prometheus metrics are stored in. The rule groups are scoped to it, because that is where their expressions are evaluated."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Monitor/accounts/[^/]+$", var.azure_monitor_workspace_id))
    error_message = "azure_monitor_workspace_id must be the resource id of an Azure Monitor workspace."
  }
}

variable "name_prefix" {
  description = "Prefix for both rule group names, so the two are recognisable as a pair and as belonging to one environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "action_group_name" {
  description = "Name of the Action Group."
  type        = string
}

variable "action_group_short_name" {
  description = "Short name of the Action Group. It appears in an SMS and at the start of a notification, and Azure caps it at twelve characters."
  type        = string

  validation {
    condition     = length(var.action_group_short_name) >= 1 && length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be between 1 and 12 characters, which is Azure's limit."
  }
}

variable "email_receivers" {
  description = <<-EOT
    Email addresses notified when an alert fires. There is no default: an Action Group with no
    receiver accepts alerts and tells nobody, which fails silently and is worse than failing to
    deploy. At least one address is required.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.email_receivers) >= 1
    error_message = "email_receivers needs at least one address, or the Action Group would notify nobody."
  }

  validation {
    condition     = length(var.email_receivers) == length(distinct(var.email_receivers))
    error_message = "email_receivers must not repeat an address: each one becomes a receiver whose name is its position in the list, so a repeat would produce two receivers with the same name and Azure would reject the group."
  }

  validation {
    condition = alltrue([
      for address in var.email_receivers : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", address))
    ])
    error_message = "Every entry in email_receivers must look like an email address."
  }
}

variable "thresholds" {
  description = <<-EOT
    The tuning of the alert rules, all of it in one place so the baseline can be read as a
    whole and changed deliberately.

    The defaults are set for a development or staging cluster and lean towards not firing.
    Durations are ISO 8601, which is the format the alert API takes — PT15M is fifteen minutes.
    A `for` duration is how long the condition has to hold before the alert fires, so it is the
    main control over noise: the thresholds decide what looks wrong, and the durations decide
    how long it has to keep looking wrong before anybody is told.

    The exceptions worth knowing about:

    * `restarts_threshold` is 3 rather than 1. Microsoft's published rule fires on any restart,
      which in a development cluster means a rollout pages somebody. Measured on this cluster,
      the largest one-hour increase across every container was 1.01.
    * `node_cpu_for` and `node_memory_for` are longer than the rest. Load on a node spikes
      during an image pull or a rollout and settles, so a short window would be noisy; half an
      hour of sustained load is a problem.
    * `restarts_window` is the period the restarts are counted over, not a delay. It is a Go
      duration because it is inside the PromQL query rather than an alert field.
  EOT
  type = object({
    node_cpu_percent      = optional(number, 85)
    node_cpu_for          = optional(string, "PT30M")
    node_memory_percent   = optional(number, 90)
    node_memory_for       = optional(string, "PT30M")
    node_not_ready_for    = optional(string, "PT15M")
    crashloop_for         = optional(string, "PT15M")
    restarts_threshold    = optional(number, 3)
    restarts_window       = optional(string, "1h")
    restarts_for          = optional(string, "PT15M")
    oom_for               = optional(string, "PT5M")
    ready_ratio_threshold = optional(number, 0.8)
    ready_state_for       = optional(string, "PT5M")
  })
  default = {}

  validation {
    condition = alltrue([
      var.thresholds.node_cpu_percent > 0 && var.thresholds.node_cpu_percent <= 100,
      var.thresholds.node_memory_percent > 0 && var.thresholds.node_memory_percent <= 100,
    ])
    error_message = "The CPU and memory thresholds are percentages, so they must be above 0 and at most 100."
  }

  validation {
    condition     = var.thresholds.ready_ratio_threshold > 0 && var.thresholds.ready_ratio_threshold < 1
    error_message = "ready_ratio_threshold is a proportion, so it must be above 0 and below 1. Microsoft's published rule uses 0.8."
  }

  validation {
    condition     = var.thresholds.restarts_threshold >= 1
    error_message = "restarts_threshold must be at least 1, or the rule would fire on a pod that has not restarted."
  }

  validation {
    condition = alltrue([
      for duration in [
        var.thresholds.node_cpu_for,
        var.thresholds.node_memory_for,
        var.thresholds.node_not_ready_for,
        var.thresholds.crashloop_for,
        var.thresholds.restarts_for,
        var.thresholds.oom_for,
        var.thresholds.crashloop_for,
        var.thresholds.ready_state_for,
      ] : can(regex("^PT[0-9]+[MH]$", duration))
    ])
    error_message = "Every alert duration must be ISO 8601 of at least a minute, such as PT5M or PT1H."
  }

  validation {
    condition     = can(regex("^[0-9]+[smhd]$", var.thresholds.restarts_window))
    error_message = "restarts_window is used inside the PromQL query, so it is a Go duration such as 1h or 30m, not ISO 8601."
  }
}

variable "tags" {
  description = "Tags applied to the Action Group and the rule groups."
  type        = map(string)
  default     = {}
}
