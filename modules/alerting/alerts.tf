# The alert rules, as two Prometheus rule groups: one for the nodes, one for the pods.
#
# Every rule is a metric rule. The Kubernetes object signals come from kube-state-metrics and the
# host figures from node-exporter, both scraped by the managed Prometheus add-on.
#
# The expressions are Microsoft's, taken from the alert template the add-on publishes
# (Azure/prometheus-collector, GeneratedMonitoringArtifacts/Default/recommendedMetricAlerts.json),
# and kept as written rather than simplified so that each rule can be compared against the
# published set and against the recording rules the add-on installs alongside it. Where a rule
# corresponds to a published one it carries the published name, so the mapping is by reading
# rather than by guessing; the node rules have no published counterpart and are named here.
#
# Two deliberate departures, both about noise:
#
#   * Repeated restarts alerts on three in an hour rather than on one. Microsoft's rule fires on
#     any increase, which in a development cluster means a single restart during a rollout notifies
#     somebody. Measured on this cluster, the largest one-hour increase across every container was
#     1.01, so the published threshold was moments away from firing on a healthy cluster.
#   * Severities are set for a real notification rather than for a data source. Microsoft marks
#     most of these Verbose (4); a crashing pod or an OOM kill is not verbose, so those sit at
#     Warning (2) and a lost node at Error (1). Nothing routes on severity yet — the point of
#     setting it now is that a route added later does not have to be added twice.
#
# One rule is quiet in a way that is easy to misread, and worth knowing before troubleshooting it:
# KubePodCrashLooping selects a metric that has no series at all on a healthy cluster. See the
# note on that rule and the README.

locals {
  # Names are what an alert shows in the portal, so the cluster is in both of them and the
  # group says which half of the stack it covers.
  node_rule_group_name = "${var.name_prefix}-node-alerts"
  pod_rule_group_name  = "${var.name_prefix}-pod-alerts"

  # The alert rules are evaluated against the workspace the metrics are stored in, and scoped to
  # the cluster they describe. Microsoft's own template passes both, and the cluster scope is
  # what ties a firing alert back to the resource it came from.
  rule_group_scopes = [
    var.azure_monitor_workspace_id,
    var.cluster_id,
  ]
}

# The nodes themselves: whether they are there, and whether they are being worked too hard.
resource "azurerm_monitor_alert_prometheus_rule_group" "node" {
  name                = local.node_rule_group_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  description = "Node health for the ${var.cluster_name} cluster: readiness, CPU and memory."
  scopes      = local.rule_group_scopes
  interval    = "PT1M"

  # A node that exists and reports itself not ready. `status=~"false|unknown"` rather than
  # `status!="true"` so that a missing label cannot be read as a failure, and the `== 1` is
  # needed because the metric is a labelled gauge with one series per condition.
  rule {
    alert      = "NodeNotReady"
    expression = <<-EOT
      kube_node_status_condition{condition="Ready", status=~"false|unknown", job="kube-state-metrics"} == 1
    EOT
    for        = var.thresholds.node_not_ready_for
    severity   = 1
    enabled    = true

    annotations = {
      summary     = "Node {{ $labels.node }} is not ready."
      description = "Node {{ $labels.node }} in {{ $labels.cluster }} has reported a Ready condition other than true for the duration of this alert. Workloads on it may be rescheduled."
    }

    # The Action Group is attached per rule rather than once per group, because that is the
    # shape the resource has. The group is created before the rules, so its id is settled by
    # the time these are sent.
    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }

  # CPU busy on a node, sustained. node_cpu_seconds_total is a counter per CPU mode per CPU, so
  # the fraction of time spent idle is what is left after averaging across those series; the
  # rest is the busy fraction.
  #
  # Fifteen minutes of short window and a thirty minute threshold: a node pegging its CPU during
  # an image pull or a rollout is normal and passes, a node sitting above the threshold for half
  # an hour is not.
  rule {
    alert      = "NodeHighCpu"
    expression = <<-EOT
      100 * (1 - avg by (cluster, instance) (rate(node_cpu_seconds_total{job="node", mode="idle"}[5m]))) > ${var.thresholds.node_cpu_percent}
    EOT
    for        = var.thresholds.node_cpu_for
    severity   = 3
    enabled    = true

    annotations = {
      summary     = "Node {{ $labels.instance }} is above ${var.thresholds.node_cpu_percent}% CPU."
      description = "Node {{ $labels.instance }} in {{ $labels.cluster }} has averaged more than ${var.thresholds.node_cpu_percent}% CPU for the duration of this alert. Pods on it may be being throttled or evicted."
    }

    # The Action Group is attached per rule rather than once per group, because that is the
    # shape the resource has. The group is created before the rules, so its id is settled by
    # the time these are sent.
    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }

  # Memory in use on a node, sustained. Availability rather than free memory: the page cache
  # counts as available because the kernel can reclaim it, so MemAvailable is the figure that
  # reflects pressure and MemFree is not.
  rule {
    alert      = "NodeHighMemory"
    expression = <<-EOT
      100 * (1 - sum by (cluster, instance) (node_memory_MemAvailable_bytes{job="node"}) / sum by (cluster, instance) (node_memory_MemTotal_bytes{job="node"})) > ${var.thresholds.node_memory_percent}
    EOT
    for        = var.thresholds.node_memory_for
    severity   = 3
    enabled    = true

    annotations = {
      summary     = "Node {{ $labels.instance }} is above ${var.thresholds.node_memory_percent}% memory."
      description = "Node {{ $labels.instance }} in {{ $labels.cluster }} has had less than ${100 - var.thresholds.node_memory_percent}% of its memory available for the duration of this alert. Pods on it may be OOM killed."
    }

    # The Action Group is attached per rule rather than once per group, because that is the
    # shape the resource has. The group is created before the rules, so its id is settled by
    # the time these are sent.
    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }
}

# The pods: whether they are starting, staying up, and staying inside their memory limit.
resource "azurerm_monitor_alert_prometheus_rule_group" "pod" {
  name                = local.pod_rule_group_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  description = "Pod health for the ${var.cluster_name} cluster: restarts, readiness and OOM kills."
  scopes      = local.rule_group_scopes
  interval    = "PT1M"

  # A container the kubelet is waiting to restart, having failed repeatedly.
  #
  # Microsoft's published KubePodCrashLooping, kept as written. max_over_time over five minutes
  # absorbs the gap between restarts, when the reason reports something else for a few seconds
  # and a point-in-time query would see nothing wrong.
  #
  # kube_pod_container_status_waiting_reason is kept by the add-on's minimal ingestion profile and
  # is emitted only for containers that are waiting right now — kube-state-metrics skips creating
  # series for running ones. On a healthy cluster it therefore has no series at all and a query
  # for it returns nothing, which is the expected state rather than a missing metric. Checking
  # whether it is collected means looking at kube_pod_container_status_waiting, which is a 0/1
  # gauge for every container; the README records how to tell the two apart.
  rule {
    alert      = "KubePodCrashLooping"
    expression = <<-EOT
      max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff", job="kube-state-metrics"}[5m]) >= 1
    EOT
    for        = var.thresholds.crashloop_for
    severity   = 2
    enabled    = true

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is in CrashLoopBackOff."
      description = "{{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) in {{ $labels.cluster }} has been restarting and failing for the duration of this alert. Check its logs and its last exit code."
    }

    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }

  # Microsoft's KubePodContainerRestart, with the threshold raised from 1 to 3.
  #
  # Restarts, counted over an hour and grouped by the controller that owns the pod. The join
  # against kube_pod_owner replaces the pod name with its controller, so a Deployment being
  # rolled reports one alert rather than one per replica.
  #
  # increase() rather than a raw counter comparison, because the metric only ever goes up.
  rule {
    alert      = "PodRestarting"
    expression = <<-EOT
      sum by (namespace, controller, container, cluster) (
        increase(kube_pod_container_status_restarts_total{job="kube-state-metrics"}[${var.thresholds.restarts_window}])
        * on(namespace, pod, cluster) group_left(controller)
          label_replace(kube_pod_owner, "controller", "$1", "owner_name", "(.*)")
      ) >= ${var.thresholds.restarts_threshold}
    EOT
    for        = var.thresholds.restarts_for
    severity   = 3
    enabled    = true

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.controller }} restarted ${var.thresholds.restarts_threshold} or more times in ${var.thresholds.restarts_window}."
      description = "Container {{ $labels.container }} of {{ $labels.controller }} in {{ $labels.namespace }} on {{ $labels.cluster }} has restarted at least ${var.thresholds.restarts_threshold} times in the last ${var.thresholds.restarts_window}. This fires before a crash loop does; the container is unstable rather than stuck."
    }

    # The Action Group is attached per rule rather than once per group, because that is the
    # shape the resource has. The group is created before the rules, so its id is settled by
    # the time these are sent.
    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }

  # Readiness across a workload, as a ratio: ready replicas over desired, for Deployments and
  # DaemonSets. Below 0.8 means a fifth of the workload is not serving.
  #
  # Microsoft's published KubePodReadyStateLow, kept as written. It replaces an earlier rule that
  # counted unready containers directly, which had two problems the ratio does not: the
  # container-level metric reads 0 for every finished Job pod, so it needed a phase join to
  # exclude the migration and bootstrap Jobs, and it counted absolute containers rather than
  # proportion, so it could not tell a one-replica Deployment losing its only pod from a
  # fifty-replica Deployment losing one.
  #
  # The ratio is 1.0 for every Cronus workload when this was written, so the rule is quiet on a
  # healthy cluster by construction rather than by a long `for` duration.
  rule {
    alert      = "KubePodReadyStateLow"
    expression = <<-EOT
      sum by (cluster,namespace,deployment)(kube_deployment_status_replicas_ready) / sum by (cluster,namespace,deployment)(kube_deployment_spec_replicas) <${var.thresholds.ready_ratio_threshold} or sum by (cluster,namespace,daemonset)(kube_daemonset_status_number_ready) / sum by (cluster,namespace,daemonset)(kube_daemonset_status_desired_number_scheduled) <${var.thresholds.ready_ratio_threshold}
    EOT
    for        = var.thresholds.ready_state_for
    severity   = 2
    enabled    = true

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.deployment }}{{ $labels.daemonset }} has fewer than ${var.thresholds.ready_ratio_threshold * 100}% of its replicas ready."
      description = "A workload on {{ $labels.cluster }} has been below ${var.thresholds.ready_ratio_threshold * 100}% ready for the duration of this alert, so a share of its replicas is not serving traffic."
    }

    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }

  # Microsoft's KubeContainerOOMKilledCount, kept as written.
  #
  # A container killed for exceeding its memory limit.
  #
  # This reads the *last* terminated reason rather than the current one: the current-reason
  # metric is not in the add-on's default keep list, so it is not there to query, while the last
  # reason is. The cost is that the value persists until the container terminates again, so this
  # alert stays firing until the pod is replaced rather than clearing on its own — which is the
  # right behaviour for an OOM kill, since the underlying request or limit still needs changing.
  rule {
    alert      = "PodOomKilled"
    expression = <<-EOT
      sum by (cluster, container, controller, namespace) (
        kube_pod_container_status_last_terminated_reason{reason="OOMKilled", job="kube-state-metrics"}
        * on(cluster, namespace, pod) group_left(controller)
          label_replace(kube_pod_owner, "controller", "$1", "owner_name", "(.*)")
      ) > 0
    EOT
    for        = var.thresholds.oom_for
    severity   = 2
    enabled    = true

    annotations = {
      summary     = "{{ $labels.namespace }}/{{ $labels.controller }} ({{ $labels.container }}) was OOM killed."
      description = "Container {{ $labels.container }} of {{ $labels.controller }} in {{ $labels.namespace }} on {{ $labels.cluster }} was killed for exceeding its memory limit. Its request and limit need raising, or the workload needs fixing."
    }

    # The Action Group is attached per rule rather than once per group, because that is the
    # shape the resource has. The group is created before the rules, so its id is settled by
    # the time these are sent.
    action {
      action_group_id = azurerm_monitor_action_group.this.id
    }
  }
}
