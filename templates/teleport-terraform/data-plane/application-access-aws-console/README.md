# AWS Console App Access

Deploy one shared Teleport host running `app_service` + `ssh_service`, with static AWS Console apps in `teleport.yaml`.

This template is designed for:
- Same-account AWS Console access by default (host role in the deployment account).
- Optional second/cross-account app with optional `external_id`.

## Usage

1. Authenticate to Teleport and export provider env:

```bash
tsh login --proxy=teleport.example.com --auth=example
eval $(tctl terraform env)
```

2. Export `TF_VAR_*` (preferred pattern):

```bash
export TF_VAR_user="engineer@example.com"
export TF_VAR_proxy_address="teleport.example.com"
export TF_VAR_teleport_version="18.6.8"
export TF_VAR_region="us-east-2"

# Label strategy
export TF_VAR_host_env="prod"
export TF_VAR_team="platform"
export TF_VAR_env="dev"

# Required app A account label
export TF_VAR_app_a_aws_account_id="<12-digit-account-id>"

# Optional app B
# export TF_VAR_enable_app_b=true
# export TF_VAR_app_b_aws_account_id="<12-digit-account-id>"
# export TF_VAR_app_b_external_id="accountA"

# Optional: disable automatic management of account A IAM roles
# (this is the default and recommended for shared accounts)
# export TF_VAR_manage_account_a_roles=false

# Optional: if existing role names differ, override account_a_roles names
# Optional: if you prefer explicit ARNs, set TF_VAR_assume_role_arns
```

3. Deploy:

```bash
terraform init
terraform apply
```

4. Verify:

```bash
tsh ls env=prod,team=platform
tsh apps ls env=dev
```

## IAM Role and Trust Handling

By default (`manage_account_a_roles=false`), this stack does not create IAM roles.
It assumes existing account A target roles by name from `account_a_roles` and uses those ARNs for host `sts:AssumeRole`.

If you set `manage_account_a_roles=true`, this stack creates and manages account A target roles:
- `TeleportReadOnlyAccess`
- `TeleportEC2Access`
- `TeleportAdminAccess`

It also wires the trust policy automatically to allow the app host IAM role to call `sts:AssumeRole`.
`TeleportAdminAccess` additionally allows account root by default (`allow_account_root=true`).

For optional account B/cross-account roles, use outputs to configure trust manually:

```bash
terraform output -raw account_a_trust_policy_json
terraform output -raw account_b_trust_policy_json
terraform output -raw host_iam_role_arn
terraform output managed_account_a_roles
```

- `account_a_trust_policy_json`: informational/reference.
- `account_b_trust_policy_json`: only present when `enable_app_b=true`.
- `managed_account_a_roles`: roles managed in this stack.

Attach `account_b_trust_policy_json` to each account B target role's trust policy (`sts:AssumeRole`), if app B is enabled.

If enabling `manage_account_a_roles=true` with pre-existing roles, import them before apply:

```bash
terraform import 'aws_iam_role.account_a["TeleportReadOnlyAccess"]' TeleportReadOnlyAccess
terraform import 'aws_iam_role.account_a["TeleportEC2Access"]' TeleportEC2Access
terraform import 'aws_iam_role.account_a["TeleportAdminAccess"]' TeleportAdminAccess
```

## Notes

- The host uses an EC2 instance profile (IMDSv2 required), so Teleport App Service assumes roles with instance credentials.
- App B is fully optional.
- No account IDs are hardcoded in template defaults.
- Keep RBAC aligned to `env` + `team` labels for consistent SSO + Access List demos.
