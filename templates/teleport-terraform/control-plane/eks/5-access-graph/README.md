# Access Graph (Identity Security)

Deploys the Teleport Access Graph service, which powers the **Identity Security** features: visualising all access paths, identifying blast radius, and surfacing crown jewels.

Requires Teleport Enterprise with the Identity Security add-on enabled in your license.

## What It Deploys

**AWS:**
- RDS Aurora Serverless v2 (PostgreSQL 16) — persistent storage for the Access Graph
- DB subnet group in the EKS private subnets
- Security group allowing PostgreSQL (5432) from within the VPC

**Kubernetes:**
- Namespace `teleport-access-graph`
- Secret `teleport-access-graph-postgres` — RDS connection URI
- Secret `teleport-access-graph-tls` — self-signed TLS cert for gRPC listener
- ConfigMap `teleport-access-graph-ca` (in `teleport-cluster` namespace) — mounted by Teleport auth pods
- Helm release `teleport-access-graph`

## Prerequisites

- Layers 1–3 applied (`1-cluster`, `2-teleport`, `3-rbac`)
- Teleport Enterprise license with Identity Security enabled
- `tsh login` / `eval $(tctl terraform env)` active

## Usage

### Step 1: Get the Teleport host CA

```bash
curl 'https://yourcluster.teleport.sh/webapi/auth/export?type=tls-host'
```

Copy the PEM output into `terraform.tfvars` as `teleport_host_ca`.

### Step 2: Apply this layer

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in proxy_address, db_password, teleport_host_ca
eval $(tctl terraform env)
terraform init
terraform apply
```

### Step 3: Enable Access Graph in the Teleport cluster

Re-apply `2-teleport` with Access Graph enabled:

```bash
cd ../2-teleport
TF_VAR_access_graph_enabled=true terraform apply
```

This updates the Teleport Helm release to:
- Set `auth.teleportConfig.access_graph.enabled = true`
- Point the auth service at the Access Graph gRPC endpoint
- Mount the CA cert so the auth service can verify the TLS connection

### Step 4: Verify

```bash
kubectl -n teleport-access-graph rollout status deployment/teleport-access-graph
```

Then open the Teleport Web UI: **Identity Security → Graph Explorer**

## Demo Points

- **Graph Explorer**: visualise which users can access which resources and through which roles
- **Crown Jewels**: identify the most-accessed or highest-privilege resources
- **Blast radius**: select any identity and see everything it can reach
- **Role changes reflected in real-time**: apply a new role in 3-rbac and watch the graph update

## RBAC

Users with the `platform-dev-access` role can view Access Graph. In this demo setup that is:
- `engineers` group (standing access)
- `senior-devs` group (standing access)

The `access_graph` resource rule (`list` + `read` verbs) is set on `platform-dev-access` in the shared RBAC module.

## Inputs

| Variable | Default | Description |
|---|---|---|
| `proxy_address` | required | Teleport proxy hostname |
| `region` | `us-east-2` | AWS region |
| `env` | `prod` | Environment label |
| `team` | `platform` | Team label |
| `teleport_namespace` | `teleport-cluster` | Teleport Kubernetes namespace |
| `db_password` | required | RDS master password |
| `teleport_host_ca` | required | PEM-encoded Teleport host CA |
| `access_graph_chart_version` | `""` | Helm chart version (empty = latest) |

## Outputs

| Output | Description |
|---|---|
| `access_graph_endpoint` | gRPC endpoint (internal Kubernetes DNS) |
| `rds_endpoint` | RDS Aurora cluster endpoint |
| `next_steps` | Post-deployment instructions |
