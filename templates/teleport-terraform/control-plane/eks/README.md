# Teleport Control Plane on EKS (Demo)

> ⚠️ **Demo Environment**: optimized for SE demos and rapid iteration. Not for production use.

This control plane is split into three layers to keep infrastructure stable while allowing fast Teleport and RBAC iteration. The same layout can scale to proxy‑peer, cloud, and standalone‑Linux control‑plane variants.

## Layout

```
control-plane/eks/
├── 1-cluster/      # EKS infrastructure (stable, rarely changed)
├── 2-teleport/     # Teleport deployment + supporting AWS/K8s resources
├── 3-rbac/         # SAML/login rules, roles, and demo apps
└── update-teleport.sh
```

## Quick Start

### 1) Deploy EKS

```bash
cd control-plane/eks/1-cluster
export TF_VAR_region="us-east-2"
export TF_VAR_name="presales"
export TF_VAR_user="you@example.com"
terraform init
terraform apply
```

### 2) Deploy Teleport

```bash
cd ../2-teleport
export TF_VAR_region="us-east-2"
export TF_VAR_proxy_address="presales.teleportdemo.com"
export TF_VAR_user="you@example.com"
export TF_VAR_teleport_version="18.4.1"
export TF_VAR_env="prod"
export TF_VAR_team="platform"
export TF_VAR_okta_metadata_url="https://your-okta.okta.com/app/.../metadata"
terraform init
terraform apply
```

### 3) Apply RBAC + demo apps

```bash
cd ../3-rbac
export TF_VAR_region="us-east-2"
export TF_VAR_proxy_address="presales.teleportdemo.com"
export TF_VAR_okta_metadata_url="https://your-okta.okta.com/app/.../metadata"
export TF_VAR_dev_team="dev"
export TF_VAR_prod_team="platform"
terraform init
terraform apply
```

## RBAC Model

All access is scoped using `env` and `team` labels:

- **dev access**: `dev-access` with `env=dev`, `team=dev`
- **platform dev access**: `platform-dev-access` with `env=dev`, `team=*`
- **prod access**: `prod-readonly-access` and `prod-access` with `env=prod`, `team=platform`

Access lists are SCIM‑managed and must match Okta group displayNames exactly:

- `Everyone` → `base-user`
- `devs` → `dev-access`, `dev-requester`
- `engineers` → `platform-dev-access`, `dev-reviewer`, `prod-requester`

Request/review roles (`dev-requester`, `prod-requester`, `dev-reviewer`) handle elevation and approvals.

Ensure apps, DBs, nodes, and desktops are labeled with the same keys to align with roles.

## SCIM Checklist

- Enable SCIM in Teleport and associate it with your SAML connector.
- In Okta, configure SCIM provisioning with the Teleport SCIM base URL and client credentials.
- Ensure Okta group `displayName` values match Access List titles exactly:
  - `Everyone`
  - `devs`
  - `engineers`
- Apply the `3-rbac` layer to create roles and SCIM Access Lists.

## SCIM/Okta Wiring (Minimal)

- Teleport: Integrations → SCIM → create integration, select your SAML connector, copy Base URL + Client ID/Secret.
- Okta: Provisioning → SCIM → paste Base URL + Client ID/Secret, enable Group Push/Assignments.
- Access Lists: `spec.title` **must** equal Okta group `displayName` (case‑sensitive).

## Teleport Updates

Use the helper script to update Teleport without touching the EKS layer:

```bash
./update-teleport.sh update-teleport 18.4.1
```

This script updates `2-teleport/terraform.tfvars` and applies only the Teleport layer.
