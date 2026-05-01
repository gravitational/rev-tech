# Standalone Control Plane (Self-Hosted, Single Node)

The simplest self-hosted Teleport deployment: a single EC2 instance running all Teleport services (auth, proxy, SSH agent). Good for learning, development environments, and demos where EKS overhead isn't justified.

For proxy peering across multiple proxy nodes, see `control-plane/proxy-peer`.

## Layout

```
control-plane/standalone/
├── 1-cluster/   # VPC, security group, S3, IAM
├── 2-teleport/  # EC2 instance, Route 53 DNS
└── 3-rbac/      # SAML connector, roles, access lists, agent auto-updates
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
cd control-plane/standalone/1-cluster
export TF_VAR_region="us-east-2"
export TF_VAR_user="you@example.com"
terraform init
terraform apply
```

### 2) Teleport instance + DNS

```bash
cd ../2-teleport
export TF_VAR_region="us-east-2"
export TF_VAR_user="you@example.com"
export TF_VAR_domain_name="example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.7.1"
# export TF_VAR_license_path="../../license.pem"  # Enterprise only
terraform init
terraform apply
```

Wait ~60 seconds for the instance to bootstrap, then retrieve the initial admin invite:

```bash
$(terraform output -raw initial_user_login_command)
```

### 3) RBAC + access lists + auto-updates

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

## What You Get

- **Single EC2 instance** running auth + proxy + SSH agent (all services multiplexed on `:443`)
- **ACME/Let's Encrypt TLS** — no certificate management needed
- **auditd** installed and running — Teleport SSH service writes session events to the Linux Audit System automatically
- **Enhanced session recording** (BPF/eBPF) enabled — captures commands, arguments, and network connections; AL2023 ships kernel 6.x so this always works
- **SAML + Okta** — connector in 3-rbac, same as proxy-peer
- **Static access lists** — `devs`, `senior-devs`, `engineers` with Terraform-managed membership (no SCIM required)
- **Agent managed updates** — `teleport_autoupdate_config` resource enables automatic rolling updates for all connected agents on a weekday schedule

## RBAC Model

| Access list | Grants |
|---|---|
| `devs` | `dev-access`, `dev-auto-access`, `dev-requester` |
| `senior-devs` | `platform-dev-access`, `dev-auto-access`, `senior-dev-requester` |
| `engineers` | `platform-dev-access`, `dev-auto-access`, `prod-readonly-access`, `dev-reviewer`, `prod-requester`, `prod-reviewer`, `editor`, `auditor` |

`base-user` is assigned automatically to all authenticated users via the SAML connector.

## Agent Managed Updates

The `3-rbac` layer creates an `autoupdate_config` resource with `mode = "enabled"` by default. To use auto-updates on agent nodes, install agents with the updater binary instead of the standard installer:

```bash
curl https://cdn.teleport.dev/install-v18.7.1.sh | bash -s -- --updater
```

Set `autoupdate_mode = "disabled"` in `terraform.tfvars` to manage agent versions manually.

## Inputs

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-2` | AWS region |
| `user` | required | Your email — used for tagging and initial admin user |
| `domain_name` | required | Route 53 hosted zone (e.g. `example.com`) |
| `proxy_address` | required | FQDN for the cluster (e.g. `teleport.example.com`) |
| `teleport_version` | `18.7.1` | Teleport version to install |
| `instance_type` | `t3.small` | EC2 instance type |
| `license_path` | `""` | Path to Enterprise license PEM (omit for Community Edition) |
| `okta_metadata_url` | required | Okta SAML metadata URL |
| `devs` | `[]` | Emails to add to the devs access list |
| `senior_devs` | `[]` | Emails to add to the senior-devs access list |
| `engineers` | `[]` | Emails to add to the engineers access list |
| `autoupdate_mode` | `"enabled"` | Agent auto-update mode (`"enabled"` or `"disabled"`) |

## Notes

- This is a demo/development deployment — not for production use.
- The auth and proxy run on the same instance; if it restarts, the cluster is briefly unavailable.
- Resources are tagged with `env`, `team`, `teleport.dev/creator`, and `ManagedBy=terraform`.
