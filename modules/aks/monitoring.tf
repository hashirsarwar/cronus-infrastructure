# What the cluster collects, and where it goes.
#
# Collection is split in two, and the split follows the stores rather than the services.
# Managed Prometheus takes the metrics, writing them to an Azure Monitor workspace through a
# data collection rule that forwards `Microsoft-PrometheusMetrics`. Container Insights takes
# the container output — stdout and stderr — and the Kubernetes events, writing them to a Log
# Analytics workspace through a rule the Container Insights extension feeds.
#
# The two rules are the mechanism that keeps that split honest. A data collection rule decides
# what is collected; naming a stream is what starts collecting it. Container Insights is
# therefore given only the log streams, and the metric streams it would otherwise collect by
# default are absent — see the monitoring variable, whose validation refuses them. That is
# deliberate: the same metrics arriving twice would be paid for twice and would make the two
# stores disagree.
#
# Both rules are named the way Microsoft's own onboarding templates name them, so a later run
# of one of those templates finds them rather than creating a second set beside them.
#
# The rules live in this module rather than in the observability module because they bind to
# the cluster: their association names it as the target, so they cannot be created until it
# exists. The workspaces they write to are passed in, which keeps the two modules from
# referring to each other.

locals {
  # Microsoft's Container Insights rule is named MSCI-<region>-<cluster>, and its Prometheus
  # rule and endpoint after the metric prefix. The cluster and the workspaces are in the same
  # region, so the region is the module's own location.
  container_insights_dcr_name = "MSCI-${var.location}-${var.name}"
  prometheus_name             = "MSProm-${var.location}-${var.name}"
}

# Container logs and Kubernetes events. The extension data source is the Container Insights
# agent, which the cluster's monitoring add-on installs; this rule is what tells it what to
# send and where.
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = local.container_insights_dcr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  kind        = "Linux"
  description = "Container Insights: container stdout and stderr, and Kubernetes events."

  destinations {
    log_analytics {
      name                  = "container-insights-workspace"
      workspace_resource_id = var.monitoring.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = var.monitoring.container_insights_streams
    destinations = ["container-insights-workspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = var.monitoring.container_insights_streams

      # The settings here are the add-on's own, not the rule's. enableContainerLogV2 selects
      # the ContainerLogV2 schema, which is the current one: each record is a structured
      # object rather than a line to be parsed, and it is the schema Microsoft is keeping.
      #
      # Namespace filtering is off, so every namespace is collected. Filtering would cut
      # volume, and with it the container output of whatever was filtered out, which is the
      # wrong saving for nonprod: the daily cap on the workspace bounds cost without
      # deciding in advance what is worth seeing.
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          namespaces             = []
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id

  # Deleting an association does not fail, it silently stops collection, so a plan that
  # offers to remove this one is worth reading twice.
  description = "Binds the Container Insights rule to the cluster. Removing it stops log and event collection."
}

# Prometheus metrics. The forwarder data source is the scraping agent the managed Prometheus
# add-on installs, and the monitor account destination is the Azure Monitor workspace the
# metrics are stored in.
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                = local.prometheus_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  kind        = "Linux"
  description = "Azure Monitor metrics profile: Prometheus metrics scraped from the cluster."

  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id

  destinations {
    monitor_account {
      name               = "prometheus-workspace"
      monitor_account_id = var.monitoring.azure_monitor_workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["prometheus-workspace"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
}

# The endpoint the scraping agent sends to, rather than the workspace's own. Microsoft's
# onboarding template creates one for the same reason: the workspace's default endpoint lives
# in a resource group Azure manages, so this keeps the whole path inside resources this
# configuration owns and can change.
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = local.prometheus_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  kind = "Linux"
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = local.prometheus_name
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
  description             = "Binds the metrics rule to the cluster. Removing it stops Prometheus metrics reaching the Azure Monitor workspace."
}
