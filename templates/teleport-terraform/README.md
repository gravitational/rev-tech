# Teleport Terraform Templates

Terraform templates and reusable modules for demonstrating Teleport features on AWS. Designed for Solution Engineers running POCs, live demos, and prospect workshops.

**Configuration:** use `export TF_VAR_*` for inputs rather than committing `terraform.tfvars` files.

## Layout

```
templates/teleport-terraform/
├── profiles/         # THE deployment surface — one composable root + presets per demo
├── data-plane/       # special-case templates a preset can't express (discovery, AWS console IAM)
├── control-plane/    # cluster blueprints (Teleport Cloud config, standalone self-hosted)
├── modules/          # shared building blocks (networking, nodes, databases, apps, desktop)
└── tools/            # validation, smoke tests, and OPA policy checks
```

**Start with profiles.** Every demo — single feature or full archetype — is a preset of the one profiles root: shared VPC, one `terraform apply`, one `terraform destroy`, demo RBAC included. The data-plane templates remain only for the flows a flag can't express (auto-discovery workflows, the AWS Console IAM ownership model) plus the SSH getting-started tutorial.

---

## Quick Start

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com

cd profiles
terraform init
terraform apply -var-file=presets/dev-demo.tfvars   # or any preset — see profiles/README.md
```

---

## Templates

### Profiles (start here)

One composable root; a preset per demo. Archetypes: `dev-demo` (~$5–7/day), `full-platform` (~$8–12/day), `cloud-native-apps` (~$3–5/day). Single-feature presets: `ssh`, `postgres`, `mysql`, `mongodb`, `cassandra`, `rds-mysql`, `grafana`, `httpbin`, `demo-panel`, `aws-console`, `windows`, `mcp`, `ansible`.

See [profiles/README.md](profiles/README.md) for usage, the preset table, demo RBAC (Bob), and the dev-demo talk track.

### Data Plane (special cases)

| Template | What It Shows | Tested |
|---|---|---|
| `server-access-ssh-getting-started` | The tutorial: SSH nodes on Amazon Linux 2023, session recording, dynamic host users | ✅ |
| `server-access-ec2-autodiscovery` | EC2 auto-discovery via SSM + IAM joining — tag an instance, it enrolls automatically | — |
| `kubernetes-access-eks-autodiscovery` | EKS auto-discovery agent — tag a cluster, it enrolls automatically | ✅ |
| `application-access-aws-console` | AWS Console federation with per-role IAM assume — first-deploy IAM ownership model | ✅ |

### Control Plane

| Template | Description |
|---|---|
| `control-plane/cloud` | Teleport Cloud tenant configuration (Teleport provider only, no infra layer) — the common SE path. |
| `control-plane/standalone` | Single-node EC2 Teleport cluster — fastest path to a working self-hosted cluster. |

The EKS control plane (Slack plugin, SCIM, Access Graph) and the proxy-peer variant now live in [tenaciousdlg/teleport-terraform](https://github.com/tenaciousdlg/teleport-terraform), which runs `presales.teleportdemo.com`.

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

### RBAC

| Module | Description |
|---|---|
| `teleport-rbac` | Canonical 12-role demo set. Deploy-once from the control-plane `3-rbac` layers; static names and labels. |
| `demo-rbac` | Per-profile demo roles + local demo user. Role names are user-prefixed so concurrent SEs don't collide; labels always match the profile's `env`/`team`. |

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

# Create the GitHub join token (see docs/github-actions-setup.md at the repo root for full YAML)
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
- Agents always install the version your cluster advertises (via `install.sh`) and stay current through [Agent Managed Updates](https://goteleport.com/docs/upgrading/agent-managed-updates/). The update schedule is managed cluster-side by the `teleport_autoupdate_config` resource in `control-plane/*/3-rbac`.
- The `application-access-aws-console` template requires `manage_account_a_roles=true` on first deploy in a fresh account to create the IAM target roles. See that template's README for the shared-account ownership pattern.
- All templates tag resources with `teleport.dev/creator`, `env`, `team`, and `ManagedBy=terraform` for cost attribution and RBAC consistency.
