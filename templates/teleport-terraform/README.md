# Teleport Terraform Templates

Terraform templates and reusable modules for demonstrating Teleport features on AWS. Designed for Solution Engineers running POCs, live demos, and prospect workshops.

**Configuration:** use `export TF_VAR_*` for inputs rather than committing `terraform.tfvars` files.

## Layout

```
templates/teleport-terraform/
├── control-plane/    # control plane blueprints (EKS, roles, SSO, plugins)
├── data-plane/       # individual use case demos (one Teleport feature per template)
├── profiles/         # multi-use-case compositions for prospect archetypes
├── modules/          # shared building blocks (networking, nodes, databases, apps, desktop)
└── tools/            # validation, smoke tests, and OPA policy checks
```

**data-plane vs. profiles:**
- **data-plane** — demo a single Teleport feature. Each template creates its own VPC.
- **profiles** — demo multiple features for a specific prospect archetype. All use cases share one VPC, one `terraform apply`, one `terraform destroy`.

---

## Quick Start (any template)

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.7.1

cd data-plane/server-access-ssh-getting-started   # or any template
terraform init && terraform apply
```

---

## Templates

### Control Plane

| Template | Description |
|---|---|
| `control-plane/eks` | EKS-based Teleport control plane: infra, Teleport, RBAC, Slack plugin, Access Graph (5 layers). |
| `control-plane/standalone` | Single-node EC2 Teleport cluster — fastest path to a working self-hosted cluster. |
| `control-plane/proxy-peer` | Self-hosted Teleport cluster with proxy peering. |
| `control-plane/cloud` | Teleport Cloud tenant configuration (Teleport provider only, no infra layer). |

### Data Plane

| Template | What It Shows | Tested |
|---|---|---|
| `server-access-ssh-getting-started` | SSH nodes on Amazon Linux 2023, session recording, dynamic host users | ✅ |
| `server-access-ec2-autodiscovery` | EC2 auto-discovery via SSM + IAM joining — tag an instance, it enrolls automatically | — |
| `application-access-grafana` | Grafana behind Teleport app service with JWT identity injection | ✅ |
| `application-access-httpbin` | HTTPBin for inspecting Teleport-injected headers in real time | ✅ |
| `application-access-aws-console` | AWS Console federation with per-role IAM assume via EC2 instance profile | ✅ |
| `application-access-demo-panel` | Flask identity panel — shows the logged-in user's Teleport identity, roles, and traits | ✅ |
| `database-access-postgres-self-managed` | Self-hosted PostgreSQL with TLS cert auth (no passwords) | ✅ |
| `database-access-mysql-self-managed` | Self-hosted MySQL with TLS cert auth | ✅ |
| `database-access-mongodb-self-managed` | Self-hosted MongoDB with TLS cert auth | ✅ |
| `database-access-cassandra-self-managed` | Self-hosted Cassandra with TLS cert auth | ✅ |
| `database-access-rds-mysql` | RDS MySQL with IAM authentication and auto user provisioning | ✅ |
| `desktop-access-windows-local` | Windows Server via browser-based RDP (no AD, local users) | ✅ |
| `machine-id-ansible` | Machine ID bot + Ansible host — certificate-based automation, no static keys | ✅ |
| `machine-id-mcp` | MCP stdio server + Machine ID bot — Claude/AI access via Teleport with full audit | ✅ |
| `kubernetes-access-eks-autodiscovery` | EKS auto-discovery agent — tag a cluster, it enrolls automatically | ✅ |

### Profiles

| Profile | Archetype | Cost | Tested |
|---|---|---|---|
| `profiles/dev-demo` | Developer "day in the life" — Bob (dev) + engineer, access requests, session locking | ~$5–7/day | ✅ |
| `profiles/windows-mongodb-ssh` | Traditional enterprise — Windows + MongoDB + Linux SSH | ~$2–4/day | — |
| `profiles/cloud-native-apps` | Modern cloud shop — Grafana + HTTPBin + RDS MySQL + AWS Console | ~$3–5/day | — |
| `profiles/full-platform` | All-up POC — every Teleport feature in one deployment | ~$8–12/day | ✅ |

See [profiles/README.md](profiles/README.md) for usage and demo flows.

---

## Modules

### Infrastructure

| Module | Description |
|---|---|
| `network` | VPC, subnets (private + public), NAT gateway, security groups, optional DB subnet group. |
| `ssh-node` | EC2 instances running Teleport SSH service with dynamic host user creation. |
| `windows-instance` | Windows Server 2022 host pre-configured for Teleport Desktop Access. |
| `desktop-service` | Linux host running `windows_desktop_service` — RDP proxy with full session recording. |

### Database

| Module | Description |
|---|---|
| `self-database` | Self-hosted database on EC2. Parameterized by `db_type`: `postgres`, `mysql`, `mongodb`, `cassandra`. Custom CA + TLS cert issued at deploy time, Teleport DB agent installed. |
| `rds-mysql` | RDS MySQL with IAM auth, Teleport agent on EC2, auto user provisioning. |

### Application

| Module | Description |
|---|---|
| `app-grafana` | Grafana server with Teleport app service. JWT header injection included. |
| `app-httpbin` | HTTPBin server with Teleport app service. Good for showing injected headers. |
| `app-aws-console-host` | EC2 host with instance profile for AWS Console role federation. |
| `app-demo-panel` | Flask identity panel — reads `Teleport-Jwt-Assertion` header, shows user/roles/traits. |

### Machine ID

| Module | Description |
|---|---|
| `machineid-bot` | Creates a Teleport bot with a role, provision token, and optional bound keypair. |
| `machineid-ansible` | EC2 host with tbot + Ansible — certificate-based SSH automation. |
| `mcp-stdio-app` | EC2 host running Teleport app service for MCP stdio server discovery. |

### Discovery

| Module | Description |
|---|---|
| `ec2-discovery-agent` | Discovery Service agent that auto-enrolls tagged EC2 instances via SSM + IAM joining. |
| `kube-discovery-agent` | Discovery Service agent that auto-enrolls tagged EKS clusters. |
| `dynamic-registration` | Teleport resource registration helper — creates `teleport_db` or `teleport_app` resources. |

Each module has its own README with variables, outputs, and usage examples.

---

## Tools

| Script | Description |
|---|---|
| `tools/terraform-templates-check.sh` | Runs `terraform fmt -check` and `terraform validate` on every template. Set `RUN_CONFTEST=1` for OPA checks. |
| `tools/smoke-test.sh` | Deploy, verify via `tsh`, and destroy a single data-plane template end-to-end. |
| `tools/smoke-test-all.sh` | Batch smoke test runner — `--quick`, `--full`, or `--templates=` modes. |
| `tools/policy/` | OPA/Conftest policies enforcing IMDSv2, EBS encryption, no public IPs, label conventions. |

### Pre-commit Hooks

```bash
brew install pre-commit terraform-docs tflint
pip install checkov
pre-commit install
pre-commit run --all-files   # baseline check
```

### GitHub Actions Deployment

Deploy a full profile without local Terraform setup — useful for spinning up a demo environment from anywhere.

**One-time setup** (run against your Teleport cluster):
```bash
# Create the CI bot with access to the Terraform provider
tctl bots add github-ci --roles=terraform-provider

# Create the GitHub join token (see docs/github-actions-setup.md for full YAML)
tctl create github-join-token.yaml
```

**Required secrets** (Settings → Secrets and variables → Actions):

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN to assume via OIDC. See [GitHub OIDC docs](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). |
| `TELEPORT_PROXY` | Your Teleport Cloud proxy hostname (e.g., `myorg.teleport.sh`) |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state. Required for scheduled teardown to work. |

**Optional secrets:**

| Secret | Description |
|---|---|
| `SLACK_WEBHOOK_URL` | If set, the teardown workflow posts a summary to Slack after each run. |

**Deploy:** Actions → **Deploy Teleport Demo** → Run workflow → pick a profile and environment.

**Destroy:** Re-run the deploy workflow with the **Destroy** checkbox checked, or trigger **Scheduled Demo Teardown** manually to clean up all profiles at once.

**Scheduled teardown:** Runs every Monday at 08:00 UTC and destroys any profiles that still have resources running. Requires `TF_STATE_BUCKET` to locate the state files.

Note: workflows are only triggerable from the default branch (`main`).

---

## Notes

- State is kept locally and gitignored. Each practitioner manages their own state.
- The `application-access-aws-console` template requires `manage_account_a_roles=true` on first deploy in a fresh account to create the IAM target roles. See that template's README for the shared-account ownership pattern.
- All templates tag resources with `teleport.dev/creator`, `env`, `team`, and `ManagedBy=terraform` for cost attribution and RBAC consistency.
