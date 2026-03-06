# Application Access — AWS Console

Deploys a Teleport host running `app_service` + `ssh_service` that federates access to the AWS Console using EC2 instance profile credentials and `sts:AssumeRole`. Supports same-account and optional cross-account access.

**Tested:** ✅ Confirmed working with `manage_account_a_roles=true`.

---

## What It Deploys

- 1 EC2 instance (t3.micro) with an IAM instance profile for `sts:AssumeRole`
- Teleport App Service hosting one or two AWS Console apps
- Optional IAM target roles (TeleportReadOnlyAccess, TeleportEC2Access, TeleportAdminAccess)
- Shared VPC/subnet/security group

---

## How It Works

The EC2 instance profile provides AWS credentials via IMDSv2. Teleport's App Service calls `sts:AssumeRole` on behalf of the user, federating them into an AWS IAM role as a signed-in Console session. The IAM role that gets assumed is determined by Teleport RBAC — different Teleport roles can map to different AWS IAM roles.

No AWS credentials are stored in Teleport. No long-lived credentials are distributed to users.

---

## Deploy

### First Deploy (fresh account — no existing IAM roles)

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.6.4
export TF_VAR_region=us-east-2
export TF_VAR_env=dev
export TF_VAR_team=platform

# Required: 12-digit AWS account ID for same-account Console access
export TF_VAR_app_a_aws_account_id=$(aws sts get-caller-identity --query Account --output text)

# Create the IAM target roles on first deploy
export TF_VAR_manage_account_a_roles=true

cd data-plane/application-access-aws-console
terraform init
terraform apply
```

### Subsequent Deploys or Shared Accounts

If IAM roles already exist (e.g., managed by a separate stack or another team member), keep `manage_account_a_roles=false` (the default) to avoid role trust-policy drift:

```bash
export TF_VAR_manage_account_a_roles=false
# Roles are referenced by name from account_a_roles variable
```

### Cross-Account (App B)

```bash
export TF_VAR_enable_app_b=true
export TF_VAR_app_b_aws_account_id=<12-digit-account-b-id>
# Optional: STS external ID for additional trust validation
export TF_VAR_app_b_external_id=my-external-id
```

After apply, attach the trust policy output to each account B role manually:

```bash
terraform output -raw account_b_trust_policy_json
# Attach this to the target roles in account B
```

---

## Verify

```bash
tsh apps ls env=dev,team=platform
tsh apps login awsconsole-dev
tsh apps config awsconsole-dev
# Open the browser URL from the config output
```

---

## IAM Role Management

### `manage_account_a_roles=true` (recommended for first deploy)

Creates and manages three IAM roles in account A:
- `TeleportReadOnlyAccess` — read-only AWS access
- `TeleportEC2Access` — EC2 management
- `TeleportAdminAccess` — broad admin access (also allows account root by default)

The instance profile trust policy is wired automatically.

### `manage_account_a_roles=false` (default — recommended for shared accounts)

Does not create IAM roles. References existing roles by name from `account_a_roles`. Safe to run concurrently with other users in the same account.

### Importing Pre-Existing Roles

If switching from `false` to `true` with roles that already exist:

```bash
terraform import 'aws_iam_role.account_a["TeleportReadOnlyAccess"]' TeleportReadOnlyAccess
terraform import 'aws_iam_role.account_a["TeleportEC2Access"]' TeleportEC2Access
terraform import 'aws_iam_role.account_a["TeleportAdminAccess"]' TeleportAdminAccess
terraform apply
```

---

## Useful Outputs

```bash
terraform output -raw account_a_trust_policy_json   # reference trust policy for account A
terraform output -raw host_iam_role_arn             # EC2 instance profile role ARN
terraform output managed_account_a_roles            # ARNs of roles created by this stack
```

---

## Shared Account Policy

For shared AWS accounts where multiple SEs deploy:
- One dedicated IAM-owner deployment manages shared roles (`manage_account_a_roles=true`)
- All other deployments use `manage_account_a_roles=false` and reference existing role names
- This prevents concurrent Terraform runs from conflicting on role trust policies

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `user` | Your email — used for tagging | **required** |
| `proxy_address` | Teleport proxy hostname | **required** |
| `teleport_version` | Teleport version | **required** |
| `app_a_aws_account_id` | 12-digit AWS account ID for same-account Console access | **required** |
| `region` | AWS region | `"us-east-2"` |
| `env` | Environment label for app registration | `"dev"` |
| `host_env` | Environment label for the host node | `"prod"` |
| `team` | Team label | `"platform"` |
| `manage_account_a_roles` | Create and manage IAM target roles | `false` |
| `enable_app_b` | Enable optional cross-account Console app | `false` |
| `app_b_aws_account_id` | Account B ID (required if `enable_app_b=true`) | `""` |
| `app_b_external_id` | STS external ID for account B trust | `""` |
