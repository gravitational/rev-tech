# Cloud Control Plane (Teleport SaaS)

This template configures a Teleport Cloud tenant using the Teleport Terraform provider. There is no infrastructure layer to provision.

## Layout

```
control-plane/cloud/
├── 1-cluster/   # no-op for SaaS
├── 2-teleport/  # SAML connector + auth preference + base roles
└── 3-rbac/      # roles and access lists scoped by env/team
```

## Prerequisites

- Teleport Cloud tenant
- `tctl` available for generating Terraform credentials
- Terraform v1.6+

## Usage

### 1) (No-op) cluster layer

```bash
cd control-plane/cloud/1-cluster
```

### 2) Teleport configuration

```bash
cd ../2-teleport
export TF_VAR_proxy_address="your-tenant.teleport.sh"
export TF_VAR_okta_metadata_url="https://your-okta.okta.com/app/.../metadata"

# Authenticate Terraform to Teleport
# (uses Teleport credentials from tctl)
eval $(tctl terraform env)

terraform init
terraform apply
```

### 3) RBAC

```bash
cd ../3-rbac
export TF_VAR_proxy_address="your-tenant.teleport.sh"
export TF_VAR_dev_team="dev"
export TF_VAR_prod_team="platform"

# Authenticate Terraform to Teleport
# (uses Teleport credentials from tctl)
eval $(tctl terraform env)

terraform init
terraform apply
```

## RBAC Model

- **dev access**: `dev-access` with `env=dev`, `team=dev`
- **platform dev access**: `platform-dev-access` with `env=dev`, `team=*`
- **prod access**: `prod-readonly-access` and `prod-access` with `env=prod`, `team=platform`

Access lists are SCIM‑managed and must match Okta group displayNames exactly:

- `Everyone` → `base-user`
- `devs` → `dev-access`, `dev-requester`
- `engineers` → `platform-dev-access`, `dev-reviewer`, `prod-requester`

Request/review roles (`dev-requester`, `prod-requester`, `dev-reviewer`) handle elevation and approvals.

Ensure resources in your tenant are labeled with `env` and `team` to match these roles.

## SCIM Checklist

- Enable SCIM in Teleport and associate it with your SAML connector.
- In Okta, configure SCIM provisioning with the Teleport SCIM base URL and client credentials.
- Ensure Okta group `displayName` values match Access List titles exactly:
  - `Everyone`
  - `devs`
  - `engineers`
- Apply the `3-rbac` layer to create roles and SCIM Access Lists.
