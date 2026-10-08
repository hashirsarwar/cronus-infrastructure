# cronus-infrastructure

Azure infrastructure for Cronus, a cloud-native food-ordering application. Terraform provisions
separate production and nonproduction environments; [cronus-gitops](https://github.com/hashirsarwar/cronus-gitops)
manages the Kubernetes deployments running on them.

## Infrastructure Highlights

- Separate production and nonproduction clusters, networks, databases and container registries.
- Private PostgreSQL access and identity-based authentication for workloads and application CI.
- Distinct runtime and migration privileges for the backend services.
- Production database high availability, backups and deletion safeguards.
- Environment-specific monitoring and alerts.

## Technology stack

Terraform, Azure, AKS and PostgreSQL.

## Environments

Dev and staging share nonproduction compute with separate namespaces, databases and workload identities.
Production uses its own cluster with a private API. Both environments share the Azure subscription,
Entra tenant and state storage account, using separate state keys.

## Quick start

Use Terraform and Azure CLI with permissions to create Azure resources, directory objects and role
assignments. Authenticate to the intended subscription and provision the shared state backend from
[bootstrap/](bootstrap/) before initializing an environment. Review the example values without
overwriting an existing deployment's settings.

```bash
az login
az account set --subscription <subscription-id>
cd environments/nonprod
terraform init
terraform validate
terraform plan
```

Use `environments/prod` for production and review the plan before applying. Complete
[PostgreSQL bootstrap](postgres-bootstrap/bootstrap.sh) as an authorized Entra administrator from a
network path to the private server, then pass identity and telemetry settings to GitOps.

Keep state and credentials out of Git. Separate state keys do not isolate storage-account access.
The configured public application edge uses HTTP; sensitive customer traffic requires verified HTTPS.

## Related repositories

| Repository | Responsibility |
| --- | --- |
| [cronus-gitops](https://github.com/hashirsarwar/cronus-gitops) | Argo CD bootstrap, Helm charts, Gateway routes and environment-specific deployments. |
| [cronus-ordering-service](https://github.com/hashirsarwar/cronus-ordering-service) | Restaurant catalogue, cart rules, order persistence and delivery integration. |
| [cronus-delivery-service](https://github.com/hashirsarwar/cronus-delivery-service) | Idempotent delivery creation and lookup in its own database. |
| [cronus-web](https://github.com/hashirsarwar/cronus-web) | Restaurant-to-order browser journey and runtime-configured telemetry. |
