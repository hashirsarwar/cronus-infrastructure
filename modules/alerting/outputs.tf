output "action_group_id" {
  description = "Resource id of the Action Group, which every alert rule in this module names as its action."
  value       = azurerm_monitor_action_group.this.id
}

output "node_rule_group_id" {
  description = "Resource id of the node alert rule group."
  value       = azurerm_monitor_alert_prometheus_rule_group.node.id
}

output "pod_rule_group_id" {
  description = "Resource id of the pod alert rule group."
  value       = azurerm_monitor_alert_prometheus_rule_group.pod.id
}
