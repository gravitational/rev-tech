# Profile: cloud-native-apps — Modern Cloud Shop

**Archetype:** SaaS companies and tech-forward enterprises running containerized apps, AWS services, and CI/CD pipelines.

Use this when the prospect uses RDS, cares about AWS Console RBAC, and wants to see the "internal tools" access story.

**Cost:** ~$3–5/day.

---

## What It Deploys

| Resource | Count | Type | Purpose |
|---|---|---|---|
| Grafana | 1 | t3.small | App Access — JWT identity injection |
| HTTPBin | 1 | t3.micro | App Access — header inspection |
| RDS MySQL | 1 | db.t3.micro | Database Access — IAM auth, auto user provisioning |
| RDS agent | 1 | t3.small | Teleport DB agent for RDS |
| AWS Console host | 1 | t3.micro | App Access — AWS role federation |
| NAT Gateway | 1 | — | ~$1.20/day fixed |

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

# AWS Console needs the current account ID
export TF_VAR_aws_account_id=$(aws sts get-caller-identity --query Account --output text)

cd profiles/cloud-native-apps
terraform init
terraform apply
```

Allow 3–5 minutes for instances to boot and register.

---

## Verify

```bash
tsh apps ls env=dev,team=platform   # grafana-dev, httpbin-dev, awsconsole-dev
tsh db ls env=dev,team=platform     # rds-mysql-dev (or similar)
```

---

## Key Demo Commands

### Grafana — JWT Identity Injection

```bash
tsh apps login grafana-dev
# Open https://grafana-dev.<proxy> — logged in automatically as your Teleport user
```

Grafana receives a signed JWT header from Teleport with the user's identity. No Grafana login page. Works for any internal tool that supports header-based auth.

### HTTPBin — Show Injected Headers

Open `https://httpbin-dev.<proxy>/headers` in a browser. Look for:
- `Teleport-Jwt-Assertion` — full signed JWT with user sub, roles, traits
- `X-Forwarded-User` — shorthand username

This is the fastest way to show exactly what Teleport injects into any backend application.

### RDS MySQL — IAM Auth and Auto User Provisioning

```bash
# First connection — alice's DB user is created automatically
tsh db login rds-mysql-dev --db-user=alice --db-name=teleport
tsh db connect rds-mysql-dev

# Connect as a different user
tsh db login rds-mysql-dev --db-user=bob --db-name=teleport
tsh db connect rds-mysql-dev
# bob's user is also auto-created on first connect
```

No database passwords are stored anywhere. Teleport issues short-lived certificates. The `--db-user` maps to MySQL roles/permissions via Teleport RBAC.

### AWS Console — Role-Based Federation

```bash
tsh apps login awsconsole-dev
tsh apps config awsconsole-dev
# Open the browser link from the config output
# AWS Console opens federated as TeleportReadOnlyAccess (or whichever role is configured)
```

The EC2 instance profile provides AWS credentials. Teleport uses `sts:AssumeRole` to federate into the target role. Different Teleport roles can map to different AWS IAM roles.

---

## AWS Console Notes

On first deploy in a fresh account, the IAM target roles (TeleportReadOnlyAccess, TeleportEC2Access, TeleportAdminAccess) need to exist. Either:
- Create them manually and reference ARNs via `console_role_arns`, or
- Let the module create them (already configured in this profile)

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `proxy_address` | Teleport proxy hostname | **required** |
| `user` | Your email — used for tagging and resource naming | **required** |
| `teleport_version` | Teleport version | **required** |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `console_role_arns` | IAM role ARNs for AWS Console | `[]` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
| `cidr_secondary_subnet` | Secondary subnet for RDS | `"10.0.2.0/24"` |
