variable "resource_group_name" {
  description = "Resource group that the identities are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the identities. Has to match the region of the resource group."
  type        = string
}

variable "aks_identity_names" {
  description = <<-EOT
    Names of the cluster's identities, keyed by controlplane and kubelet. Both are
    required: a cluster has exactly one of each, whatever runs on it.
  EOT
  type = object({
    controlplane = string
    kubelet      = string
  })
}

variable "workload_identity_names" {
  description = <<-EOT
    Names of the workload identities, keyed by application environment and service,
    for example ordering_dev. This is a map rather than a fixed object because the
    set differs per environment: nonprod carries dev and staging workloads, prod
    will carry prod.
  EOT
  type        = map(string)
}

variable "migration_identity_names" {
  description = <<-EOT
    Names of the database migration identities, keyed by the same application environment
    and service keys as workload_identity_names, for example ordering_dev.

    Separate from the workload identities because a migration identity is granted something
    the running application must not have: the right to create and change schema objects.
    Keyed identically so that a workload and its migrations cannot drift apart, and so that
    adding an application environment means adding one row in two places rather than
    inventing a scheme.
  EOT
  type        = map(string)
}

variable "security_groups" {
  description = <<-EOT
    Entra security groups to create, keyed by purpose, for example postgres_admins.
    Each group is created empty unless members are given; a group with nobody in it
    grants nothing, so a purpose that exists only to administer something needs at
    least one member. Terraform owns the membership, so a group not listed here is
    left alone and a member removed from the list is removed from the group.
  EOT
  type = map(object({
    name        = string
    description = optional(string)
    members     = optional(set(string), [])
  }))
  default = {}
}

variable "oidc_issuer_url" {
  description = "OIDC issuer of the cluster whose tokens workloads may exchange, from the AKS module. Null when nothing is federated."
  type        = string
  default     = null
}

variable "federated_credentials" {
  description = <<-EOT
    Federated identity credentials, keyed by the credential's name in Microsoft Entra ID.
    Each one lets a Kubernetes service account exchange its own token for a token on one
    of the workload identities, so a workload reaches Azure without a secret stored in
    the cluster.

    The subject names a namespace and service account, which belong to cronus-gitops
    rather than here, so this is the one string the two repositories have to agree on.
    It is written out rather than derived, because a subject that drifts from the real
    service account fails only when a pod first tries to sign in.
  EOT
  type = map(object({
    identity = string
    subject  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for credential in values(var.federated_credentials) :
      contains(keys(var.workload_identity_names), credential.identity)
    ])
    error_message = "Every credential's identity must be one of the workload identity keys, for example ordering_dev."
  }

  validation {
    condition = alltrue([
      for credential in values(var.federated_credentials) :
      can(regex("^system:serviceaccount:[a-z0-9]([a-z0-9-]*[a-z0-9])?:[a-z0-9]([a-z0-9-]*[a-z0-9])?$", credential.subject))
    ])
    error_message = "Every subject must name a Kubernetes service account, for example system:serviceaccount:cronus-dev:cronus-ordering-service."
  }

  validation {
    condition     = length(var.federated_credentials) == 0 || var.oidc_issuer_url != null
    error_message = "oidc_issuer_url is required as soon as federated credentials are declared: a credential has to name the issuer whose tokens it trusts."
  }
}

variable "migration_federated_credentials" {
  description = <<-EOT
    Federated identity credentials for the database migration identities, keyed by the
    credential's name in Microsoft Entra ID. The issuer is the same cluster as the workload
    credentials, so these differ only in which identity they federate and which service
    account presents the token.

    Like the workload credentials, the subject names a namespace and service account that
    cronus-gitops owns, so it is written out rather than derived. The service account is
    deliberately not the one the deployment runs as: that is what keeps a pod serving
    traffic from being able to assume the identity that may change the schema.
  EOT
  type = map(object({
    identity = string
    subject  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for credential in values(var.migration_federated_credentials) :
      contains(keys(var.migration_identity_names), credential.identity)
    ])
    error_message = "Every credential's identity must be one of the migration identity keys, for example ordering_dev."
  }

  validation {
    condition = alltrue([
      for credential in values(var.migration_federated_credentials) :
      can(regex("^system:serviceaccount:[a-z0-9]([a-z0-9-]*[a-z0-9])?:[a-z0-9]([a-z0-9-]*[a-z0-9])?$", credential.subject))
    ])
    error_message = "Every subject must name a Kubernetes service account, for example system:serviceaccount:cronus-dev:cronus-ordering-migrations."
  }

  validation {
    condition     = length(var.migration_federated_credentials) == 0 || var.oidc_issuer_url != null
    error_message = "oidc_issuer_url is required as soon as federated credentials are declared: a credential has to name the issuer whose tokens it trusts."
  }
}

variable "ci_identity_names" {
  description = <<-EOT
    Identities that a continuous integration system assumes through federation, keyed by
    the application they build, for example web. A map because the set of applications
    grows, and because the key is what the federation and the registry permissions refer
    to rather than the identity's own name.

    These are separate from the workload identities on purpose. A workload identity belongs
    to something running in the cluster; a CI identity belongs to a repository, and it is
    assumed from outside the cluster entirely.
  EOT
  type        = map(string)
  default     = {}
}

variable "github_federated_credentials" {
  description = <<-EOT
    Federated identity credentials that trust GitHub Actions, keyed by the credential's
    name in Microsoft Entra ID. GitHub is the issuer rather than the cluster, so the
    issuer is fixed here and the subject names the repository and ref that may assume the
    identity. Nothing about the workflow is a secret: GitHub signs a token describing the
    run, and this is the statement of which runs are acceptable.

    The subject has to be the one GitHub actually issues. Repositories created after
    15 July 2026 carry immutable subjects, which name the owner and repository by id as
    well as by name because a name can be reused after a rename or transfer:
    repo:owner@owner-id/repository@repository-id:ref:refs/heads/branch. GitHub will not
    issue the shorter form for those repositories, so a credential written against it
    never matches and the failure appears only as an authentication error in a run.
  EOT
  type = map(object({
    identity = string
    subject  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for credential in values(var.github_federated_credentials) :
      contains(keys(var.ci_identity_names), credential.identity)
    ])
    error_message = "Every GitHub credential's identity must be one of the CI identity keys, for example web."
  }

  validation {
    condition = alltrue([
      for credential in values(var.github_federated_credentials) :
      can(regex("^repo:[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(@[0-9]+)?/[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(@[0-9]+)?:(ref:refs/(heads|tags)/[^:]+|pull_request|environment:[^:]+)$", credential.subject))
    ])
    error_message = <<-EOT
      Every subject must be a GitHub OIDC subject: repo:<owner>/<repository> followed by
      ref:refs/heads/<branch>, ref:refs/tags/<tag>, pull_request or environment:<name>.

      A repository created after 15 July 2026 also carries its owner and repository ids,
      because GitHub issues immutable subjects for those and will not issue the shorter
      form even when claims are customised:
      repo:hashirsarwar@45683359/cronus-web@1402723115:ref:refs/heads/main
    EOT
  }
}

variable "tags" {
  description = "Tags applied to the Azure resources. Entra groups are directory objects and cannot be tagged."
  type        = map(string)
  default     = {}
}
