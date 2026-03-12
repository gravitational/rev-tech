# Profile: full-platform — All-Up POC

**Archetype:** Large enterprise evaluating Teleport across the entire stack.

Use this for broad technical POCs, formal evaluations, or an always-on internal demo environment that showcases every Teleport feature category in one deployment.

**Cost:** ~$8–12/day. Always destroy after the demo.

---

## What It Deploys

| Resource | Count | Type | Purpose |
|---|---|---|---|
| SSH nodes | 2 | t3.micro | Server Access |
| PostgreSQL (self-hosted) | 1 | t3.small | Database Access — cert auth |
| MongoDB (self-hosted) | 1 | t3.small | Database Access — cert auth |
| RDS MySQL | 1 | db.t3.micro | Database Access — IAM auth, auto user provisioning |
| RDS agent | 1 | t3.small | Teleport DB agent for RDS |
| Grafana | 1 | t3.small | App Access — JWT identity injection |
| HTTPBin | 1 | t3.micro | App Access — header inspection |
| Demo Panel | 1 | t3.micro | App Access — Flask identity panel |
| AWS Console host | 1 | t3.micro | App Access — AWS role federation |
| Windows Server | 1 | t3.medium | Desktop Access target |
| Desktop Service | 1 | t3.small | Linux RDP proxy |
| MCP stdio host | 1 | t3.small | Machine ID + AI/Claude integration |
| NAT Gateway | 1 | — | ~$1.20/day fixed |

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.7.1

# Optional — demo panel defaults to https://github.com/tenaciousdlg/app-demo-panel
# export TF_VAR_demo_panel_app_repo=https://github.com/your-org/app-demo-panel

# Optional
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd profiles/full-platform
terraform init
terraform apply
```

Allow 5–8 minutes for all instances to boot and register.

---

## Verify

```bash
tsh ls                              # SSH nodes
tsh db ls                           # postgres-dev, mongodb-dev, rds-mysql-dev (or similar)
tsh apps ls                         # grafana-dev, httpbin-dev, demo-panel-dev, awsconsole-dev
# Desktops: web UI only — https://<proxy> → Windows Desktops
tsh mcp ls                          # mcp-filesystem-dev
```

---

## Key Demo Commands

### Server Access

```bash
tsh ls env=dev,team=platform
tsh ssh ec2-user@dev-ssh-0          # dynamic host user creation
# In session: w, who, last — Teleport user visible in audit
```

### Database Access

```bash
# PostgreSQL (self-hosted, cert auth)
tsh db login postgres-dev --db-user=writer --db-name=postgres
tsh db connect postgres-dev

# MongoDB (self-hosted, cert auth)
tsh db login mongodb-dev --db-user=writer
tsh db connect mongodb-dev

# RDS MySQL (IAM auth, auto user provisioning)
tsh db login rds-mysql-dev --db-user=alice
tsh db connect rds-mysql-dev
# alice's DB user is created automatically on first connect
```

### Application Access

```bash
# Grafana — JWT identity injection
tsh apps login grafana-dev
# Open https://grafana-dev.<proxy> — logged in as Teleport user automatically

# HTTPBin — show injected headers
# Open https://httpbin-dev.<proxy>/headers — look for Teleport-Jwt-Assertion

# Demo Panel — shows parsed identity
# Open https://demo-panel-dev.<proxy>

# AWS Console
tsh apps login awsconsole-dev
# Open link from config — browser opens to AWS Console federated as TeleportReadOnlyAccess
```

### Desktop Access

Web UI only: open `https://<proxy>` → **Windows Desktops** → **Connect**.

### Machine ID + MCP

```bash
# Configure Claude Desktop or any MCP client
tsh mcp ls
tsh mcp config mcp-filesystem-dev
# Paste output into Claude Desktop settings
```

---

## AWS Console Notes

The AWS Console app uses EC2 instance profile credentials for `sts:AssumeRole`. On first deploy in a fresh account, create the IAM target roles:

```bash
export TF_VAR_console_role_arns='["arn:aws:iam::ACCOUNT_ID:role/TeleportReadOnlyAccess","arn:aws:iam::ACCOUNT_ID:role/TeleportEC2Access","arn:aws:iam::ACCOUNT_ID:role/TeleportAdminAccess"]'
```

Or let the module create them by setting `manage_account_a_roles=true` in the `app-aws-console-host` module (already done in this profile).

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
| `teleport_version` | Teleport version to install on all nodes | **required** |
| `demo_panel_app_repo` | Git URL for the Flask demo panel app | `https://github.com/tenaciousdlg/app-demo-panel` |
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `console_role_arns` | IAM role ARNs for AWS Console assume | `[]` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
| `cidr_secondary_subnet` | Secondary subnet for RDS | `"10.0.2.0/24"` |
