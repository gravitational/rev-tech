# Teleport Server Access - SSH Getting Started

This template deploys a minimal AWS environment with Teleport registered SSH nodes. These are suitable for demos, workshops, and customer proof of value. It is based on the official [Teleport Server Access Getting Started Guide](https://goteleport.com/docs/enroll-resources/server-access/getting-started/) but automates the provisioning end to end.

---

## What This Template Demonstrates

- Teleport SSH Service running on **Amazon Linux 2023** EC2 instances
- Automatic node enrollment via short-lived **provisioning token**
- Environment-aware labeling for RBAC:
  - `env = dev | stage | prod`
  - `team = platform | sre | app-team`
- AWS networking baseline (VPC, subnets, NAT gateway, security group)
- Multi-node deployments via `agent_count` (e.g. 3 SSH nodes)
- Each EC2 instance also runs **nginx** as a “something is running” service

---

## Directory Layout

```bash
templates/
└── teleport-terraform/
    ├── modules/
    │   ├── network/
    │   └── ssh-node/
    └── server-access-ssh-getting-started/
        ├── main.tf
        ├── variables.tf
        └── README.md   ← (this file)
```

This template consumes the shared `network` and `ssh-node` modules

---

## Prerequisites

- Terraform > 1.6
- AWS credentials configured (`aws configure`, SSO, or env vars)
- A Teleport cluster (Cloud or Enterprise) with:
  - A valid proxy address (`example.teleport.sh`)
  - A user/role with permissions to see/join nodes matching the labels you deploy
  - Authentication to the cluster with Terraform (i.e. `eval $(tctl terraform env)`)

---

## Quick Start

0. Confirm auth to AWS and Teleport (recommend using `eval` command)

Running this can confirm AWS auth (user needs to confirm permissions to create resources)
```bash
aws sts get-caller-identity
```

The built-in `terraform-provider` role can be used with the `eval` command for a one-off auth to a Teleport cluster for a Terraform deployment.

```bash
tsh login --proxy=example.teleport.sh:443 --auth=sso
eval $(tctl terraform env)
```

1. Set variables (preferred) or use a tfvars file:

```bash
export TF_VAR_user="user@example.com"
export TF_VAR_proxy_address="your-proxy.teleport.sh"
export TF_VAR_env="dev"
export TF_VAR_team="platform"
export TF_VAR_region="us-east-2"
```

Or:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. From the template directory

```bash
cd data-plane/server-access-ssh-getting-started
terraform init
```

3. Create a plan

```bash
terraform plan
```

4. Apply

```bash
terraform apply
```

After 1-2 minutes nodes will appear

```bash
tsh ls env=dev,team=platform
```

example:

```bash
❯ tsh ls env=dev,team=platform
Node Name Address    Labels                                                                       
--------- ---------- ---------------------------------------------------------------------------- 
dev-ssh-0 ⟵ Tunnel   disk_used=14%,hostname=dev-ssh-0,load_average=0.67,team=platform,env=dev 
dev-ssh-1 ⟵ Tunnel   disk_used=14%,hostname=dev-ssh-1,load_average=0.78,team=platform,env=dev 
dev-ssh-2 ⟵ Tunnel   disk_used=14%,hostname=dev-ssh-2,load_average=0.48,team=platform,env=dev 
```

SSH into a node

```bash
tsh ssh ec2-user@dev-ssh-0
```

### Input Variables

| Variable           | Description                                                   | Default      |
| ------------------ | ------------------------------------------------------------- | ------------ |
| `user`             | Used for tagging & node name prefix                           | **required** |
| `proxy_address`    | Teleport proxy hostname (no scheme, no port)                  | **required** |
| `env`              | Label determining access env (`dev`, `stage`, `prod`)        | `"dev"`      |
| `team`             | Label determining team ownership (`platform`, `sre`, `app`)   | `"platform"` |
| `agent_count`      | Number of SSH nodes to deploy                                 | `3`          |
| `instance_type`    | EC2 type                                                      | `t3.micro`   |
| `region`           | AWS region                                                    | `us-east-2`  |

### RBAC Examples

Nodes register with labels

```bash
env: dev  # or whatever you pass in var.env
team: platform  # or whatever you pass in var.team
```

Developer Role

```bash
allow:
  node_labels:
    env: ["dev", "stage"]
    team: ["app"]
  logins: ["{{external.username}}"]

```

SRE/Platform Role

```bash
allow:
  node_labels:
    env: ["dev", "stage", "prod"]
    team: ["platform", "sre", "app"]
  logins: ["ec2-user", "ubuntu"]
```

#### Dynamic Labels

[Dynamic labels](https://goteleport.com/docs/zero-trust-access/rbac-get-started/labels/#apply-dynamic-labels-using-commands) are also added to the nodes via commands arguements in `/etc/teleport.yaml`.

### What This Template Creates (AWS)
- VPC (`10.0.0.0/16`)
- Public subnet 
- Private subnet 
- NAT Gateway
- Route tables
- Security group
- EC2 instances running Teleport node service and nginx process

Everything is tagged with 

```bash
teleport.dev/creator = <user>
env                 = <env>
ManagedBy            = terraform
Example              = server-access-ssh-getting-started
```

### Cleanup

```bash
terraform destroy
```

## WARNING

> ℹ️ **State management:** Terraform state is kept locally per user and ignored via `.gitignore`. Do not commit `.tfstate`, `.tfvars`, or `.terraform` directories—each practitioner should manage their own state/backend when running this template.
