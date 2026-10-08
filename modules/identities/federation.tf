locals {
  # Microsoft Entra accepts exactly one audience for direct workload identity federation,
  # and it does not depend on who the issuer is. Fixed here rather than passed in: a wrong
  # audience is accepted at plan time and fails at token exchange with AADSTS700212 the
  # first time something signs in.
  federation_audience = ["api://AzureADTokenExchange"]

  # Every GitHub repository issues tokens from the same issuer, so unlike the cluster's
  # issuer it is a constant rather than an input.
  github_oidc_issuer = "https://token.actions.githubusercontent.com"
}

# Federation between a Kubernetes service account and one of the workload identities.
#
# The credential is the entire trust relationship: tokens from this cluster's issuer,
# carrying this subject and this audience, are accepted as this identity. Nothing is
# shared as a result — there is no client secret anywhere, so there is nothing to rotate
# and nothing to leak into the cluster.
#
# These live here rather than in the AKS module because a credential belongs to the
# identity it federates. The issuer comes in as an input, which means the two modules
# reference each other; Terraform orders that correctly because no single value is
# involved in a loop — the cluster needs the cluster identities, and a credential needs
# the issuer and a workload identity, but no workload identity feeds the cluster.
#
# The credentials are created before the service accounts they name. Until cronus-gitops
# creates those namespaces and service accounts, a credential is inert rather than wrong:
# nothing can present the subject yet, and nothing is granted to the subject here either.

resource "azurerm_federated_identity_credential" "this" {
  for_each = var.federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.value.identity].id
  issuer                    = var.oidc_issuer_url
  subject                   = each.value.subject

  # The audience Microsoft Entra requires for direct workload identity federation. It is
  # not an environment value but the protocol itself, which is why it is fixed here: a
  # wrong audience is accepted at plan time and fails at token exchange with AADSTS700212
  # the first time a pod signs in. AKS also offers identity bindings, which use a
  # different audience and route exchange through a proxy; enabling those would mean
  # projecting a second token rather than changing this.
  audience = local.federation_audience
}

# Federation between the job that migrates the database and one of the migration identities.
#
# The same trust relationship as the workload credentials above, pointed at a job rather
# than at the pod serving traffic. Kept separate rather than folded in because the service
# account a job runs as must not be the one the deployment runs as: a migration identity is
# the one granted the right to change the schema, so a pod that could assume it would
# collapse the two identities back into one.
resource "azurerm_federated_identity_credential" "migrations" {
  for_each = var.migration_federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.migrations[each.value.identity].id
  issuer                    = var.oidc_issuer_url
  subject                   = each.value.subject
  audience                  = local.federation_audience
}

# Federation between a GitHub Actions workflow and one of the CI identities.
#
# A workflow on an allowed ref asks GitHub for a token, GitHub signs one describing the
# run, and Microsoft Entra exchanges it for a token on this identity. The Azure CLI and
# the registry never see a credential that outlives the job, so there is nothing to store
# in repository secrets and nothing to rotate.
#
# The subject is the security control. Restricting it to a ref means a pull request from a
# fork, which also runs this workflow, cannot assume the identity: the ref it would claim
# is not the one named here.
resource "azurerm_federated_identity_credential" "github" {
  for_each = var.github_federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.ci[each.value.identity].id
  issuer                    = local.github_oidc_issuer
  subject                   = each.value.subject
  audience                  = local.federation_audience
}
