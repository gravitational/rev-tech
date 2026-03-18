# Proxy-Peer Control Plane (Self-Hosted)

Self-hosted Teleport cluster with proxy peering enabled. Pairs a single auth/proxy node with one or more proxy peers for horizontal scaling of user-facing connections.

## Layout

```
control-plane/proxy-peer/
├── 1-cluster/   # networking, IAM, and S3
├── 2-teleport/  # auth/proxy + peer instances, DNS
└── 3-rbac/      # SAML connector, roles, and access lists
```

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform v1.6+
- Route 53 hosted zone for your domain
- Okta SAML app configured with your cluster's ACS URL
- Optional: Teleport Enterprise license file

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
export TF_VAR_teleport_version="18.7.1"
export TF_VAR_proxy_count=1
# export TF_VAR_license_path="../../license.pem"  # Enterprise only
terraform init
terraform apply
```

The auth/proxy node writes the initial admin invite link to S3 — check the Terraform output for the exact `tctl` command.

### 3) RBAC

```bash
cd ../3-rbac
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_okta_metadata_url="https://your-okta.okta.com/app/.../metadata"

eval $(tctl terraform env)
terraform init
```

Copy the example vars file and populate your user lists:

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — add emails for devs, senior_devs, engineers
terraform apply
```

This layer creates the Okta SAML connector, auth preference, all 12 demo roles, and static access lists with the members you specified.

## RBAC Model

Three-tier persona model — roles are managed by `modules/teleport-rbac` and access list membership is Terraform-managed (no SCIM required):

| Access list | Grants |
|---|---|
| `devs` | `dev-access`, `dev-auto-access`, `dev-requester` |
| `senior-devs` | `platform-dev-access`, `dev-auto-access`, `senior-dev-requester` |
| `engineers` | `platform-dev-access`, `dev-auto-access`, `prod-readonly-access`, `dev-reviewer`, `prod-requester`, `prod-reviewer`, `editor`, `auditor` |

`base-user` is assigned automatically to all authenticated users via the SAML connector's `attributes_to_roles` (Everyone → base-user).

Resources must be labeled `env=dev`/`team=dev` (dev tier) or `env=prod`/`team=platform` (prod tier) to match the role label matchers.

## Notes

- Only a single proxy `public_addr` should be configured; multiple values can cause redirect loops.
- This is a demo deployment — not for production use.
