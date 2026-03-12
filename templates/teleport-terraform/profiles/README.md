# Profiles

Profiles compose multiple data-plane use cases into a single Terraform root module for common prospect archetypes. Instead of deploying and managing individual templates, one `terraform apply` stands up an entire scenario.

**Key difference vs. data-plane templates:** Profiles share a single VPC across all use cases. Individual data-plane templates each create their own VPC (useful for isolation, one-feature demos). Profiles trade isolation for simplicity — one network, one state file, one `terraform destroy`.

---

## Available Profiles

### `dev-demo` — Developer Day in the Life

**Archetype:** Any engineering org evaluating Teleport for day-to-day developer access.
**Use when:** You want a focused narrative-driven demo with two personas (Bob the dev, $USER the engineer).
**Cost:** ~$5–7/day.

**Includes:**
- 2 dev SSH nodes + 1 prod SSH node (invisible to Bob without approval)
- Self-hosted PostgreSQL + MongoDB (cert auth, no passwords)
- Grafana (JWT identity injection)
- HTTPBin (raw header inspection)
- Windows Server + Desktop Service (browser-based RDP)
- MCP stdio app + bot (AI/Claude integration)
- Ansible Machine ID bot

**Demo flow:**
1. Bob logs in — sees only dev-labeled resources
2. Bob SSHs to a dev node — Teleport creates a host user dynamically
3. Bob connects to postgres-dev via `tsh db connect` — no password
4. Bob submits an access request for prod access
5. $USER approves in Slack — prod-server appears in Bob's `tsh ls`
6. Bob SSHs to prod-server — $USER watches the live session and can lock it
7. $USER walks the audit trail in the UI

**Deploy:** See [dev-demo/README.md](dev-demo/README.md).

---

### `cloud-native-apps` — Modern Cloud Shop

**Archetype:** SaaS companies and tech-forward enterprises running containerized apps and AWS services.
**Use when:** Prospect uses RDS, cares about AWS Console RBAC, and wants the internal tools story.
**Cost:** ~$3–5/day.

**Includes:**
- Grafana (JWT identity injection — "internal tools" story)
- HTTPBin (JWT/header inspection)
- RDS MySQL (IAM auth, auto user provisioning — no DB passwords ever)
- AWS Console app access (per-role federation via EC2 instance profile)

**Deploy:** See [cloud-native-apps/README.md](cloud-native-apps/README.md).

---

### `full-platform` — All-Up POC

**Archetype:** Large enterprise evaluating Teleport across the entire stack.
**Use when:** Broad technical audience, formal POC, or internal demo environment.
**Cost:** ~$8–12/day. Always destroy after the demo.

**Includes:**
- 2 Linux SSH nodes
- Self-hosted PostgreSQL + MongoDB
- RDS MySQL (IAM auth)
- Grafana + HTTPBin + Demo Panel + AWS Console
- Windows Server + Desktop Service
- MCP stdio bot (AI/Claude integration)

**Deploy:** See [full-platform/README.md](full-platform/README.md).

---

## Usage (all profiles)

```bash
cd profiles/<profile-name>

# Required
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.7.1

# Optional overrides
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

terraform init
terraform apply

# After the demo
terraform destroy
```

After `apply`, Teleport resources are registered and labeled. Use `tsh ls`, `tsh db ls`, `tsh apps ls` to verify everything enrolled.

## One-Click Deployment via GitHub Actions

Deploy any profile without a local Terraform setup using the [`teleport-demo-deploy`](../../../.github/workflows/teleport-demo-deploy.yml) workflow. Go to **Actions → Deploy Teleport Demo → Run workflow** and fill in the form. Requires `AWS_ROLE_ARN` and `TELEPORT_IDENTITY` secrets.

## Adding a New Profile

1. Create a directory under `profiles/` with a descriptive archetype name.
2. Write `main.tf` using modules from `../../modules/` — do **not** call data-plane templates (they create their own VPCs; profiles share one).
3. Add `variables.tf`, `outputs.tf`, and `terraform.tfvars.example`.
4. Add an entry to this README and to the root `README.md`.
5. Run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` to generate the lock file.
