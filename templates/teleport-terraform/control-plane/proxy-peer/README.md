# Proxy‑Peer Control Plane (Linux)

Self‑hosted Teleport cluster with proxy peering enabled. This is an advanced demo that pairs a single auth/proxy node with one or more proxy peers.

Guides used:
- Self‑Hosted Demo Cluster
- Proxy Peering Architecture
- Proxy Peering Migration
- Networking / public_addr

## Layout

```
control-plane/proxy-peer/
├── 1-cluster/   # networking, IAM, and S3
├── 2-teleport/  # auth/proxy + peer instances, DNS
├── 3-rbac/      # Teleport roles aligned to env/team
```

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform v1.6+
- Teleport Enterprise license at `control-plane/license.pem`

## Usage

### 1) Networking + IAM + S3

```bash
cd control-plane/proxy-peer/1-cluster
export TF_VAR_region="us-east-2"
export TF_VAR_user="you@example.com"
export TF_VAR_env="dev"
export TF_VAR_team="platform"
terraform init
terraform apply
```

### 2) Teleport instances + DNS

```bash
cd ../2-teleport
export TF_VAR_region="us-east-2"
export TF_VAR_user="you@example.com"
export TF_VAR_env="dev"
export TF_VAR_team="platform"
export TF_VAR_parent_domain="example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.4.1"
export TF_VAR_proxy_count=1
terraform init
terraform apply
```

### 3) RBAC (env/team)

```bash
cd ../3-rbac
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_okta_metadata_url="https://your-okta.okta.com/app/.../metadata"
export TF_VAR_dev_team="dev"
export TF_VAR_prod_team="platform"
eval $(tctl terraform env)
terraform init
terraform apply
```

## Notes

- The auth/proxy node writes the initial user invite link to S3; see the output for the exact command.
- Only a single proxy `public_addr` should be configured; multiple values can cause redirects to the first address.
- This is a demo deployment; not for production use.

## RBAC Model

- **dev access**: `dev-access` with `env=dev`, `team=dev`
- **platform dev access**: `platform-dev-access` with `env=dev`, `team=*`
- **prod access**: `prod-readonly-access` and `prod-access` with `env=prod`, `team=platform`

Access lists are SCIM‑managed and must match Okta group displayNames exactly:

- `Everyone` → `base-user`
- `devs` → `dev-access`, `dev-requester`
- `engineers` → `platform-dev-access`, `dev-reviewer`, `prod-requester`

Request/review roles (`dev-requester`, `prod-requester`, `dev-reviewer`) handle elevation and approvals.

## SCIM Checklist

- Enable SCIM in Teleport and associate it with your SAML connector.
- In Okta, configure SCIM provisioning with the Teleport SCIM base URL and client credentials.
- Ensure Okta group `displayName` values match Access List titles exactly:
  - `Everyone`
  - `devs`
  - `engineers`
- Apply the `3-rbac` layer to create roles and SCIM Access Lists.
