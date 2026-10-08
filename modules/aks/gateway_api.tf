# azurerm owns add-on enablement and nginx; AzAPI updates only the unsupported Gateway properties.
# Use azapi_update_resource so cluster ownership and lifecycle stay with azurerm.
# See README.md for the ingress profile ownership split.

resource "azapi_update_resource" "gateway_api" {
  # Gateway properties require API 2026-02-01 or later.
  # Use 2026-07-01 so the read-merge-write update preserves newer cluster properties.
  type        = "Microsoft.ContainerService/managedClusters@2026-07-01"
  resource_id = azurerm_kubernetes_cluster.this.id

  body = {
    properties = {
      ingressProfile = {
        # Installs the Gateway API custom resource definitions from the standard release
        # channel. The implementation below needs them: the add-on's operator looks for
        # them and gets stuck in a crash loop without them. Only standard channel CRDs are
        # permitted here, so experimental ones have to be removed from the cluster first.
        gatewayAPI = {
          installation = var.gateway_api.installation
        }

        webAppRouting = {
          # This is sidecar-less Gateway ingress, not the service mesh add-on.
          # Leave enabled and nginx to azurerm so each ingress property has one writer.
          gatewayAPIImplementations = {
            appRoutingIstio = {
              mode = var.gateway_api.app_routing_istio_mode
            }
          }
        }
      }
    }
  }

  # The cluster reference orders this after azurerm; node pools need an explicit dependency.
  # Concurrent pool creation caused AKSOperationPreempted on the first production apply.
  # Wait for every pool; reassert Gateway fields if a later azurerm-only update ever removes them.
  depends_on = [
    azurerm_kubernetes_cluster_node_pool.user
  ]

  # Read back into state so the applied profile can be inspected with `terraform output`
  # instead of by querying the cluster. What Azure ended up with is the whole point, and it
  # is not something a plan can show.
  response_export_values = ["properties.ingressProfile"]
}
