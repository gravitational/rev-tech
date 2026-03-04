# Profiles

Profiles compose multiple data-plane use cases into a single Terraform root module for common prospect archetypes. Instead of deploying and managing individual templates, run one `terraform apply` to stand up an entire scenario.

**Key difference vs. data-plane templates:** Profiles share a single VPC across all use cases. Individual templates each create their own VPC (useful for isolation). Profiles trade isolation for simplicity — one network, one state file, one `terraform destroy`.

## Available Profiles

### `windows-mongodb-ssh`

**Archetype:** Traditional enterprise — Windows desktops, MongoDB, Linux servers.
**Use when:** Prospect is a financial services / healthcare / legacy enterprise shop.
**Includes:** SSH nodes, self-hosted MongoDB, Windows Desktop Access.

### `cloud-native-apps`

**Archetype:** Modern cloud shop — containerized apps, AWS services, CI/CD.
**Use when:** Prospect runs internal tools, uses RDS, and cares about AWS Console RBAC.
**Includes:** Grafana, HTTPBin, RDS MySQL, AWS Console app access.

### `full-platform`

**Archetype:** All-up POC — evaluating Teleport across the entire stack.
**Use when:** Broad technical audience, formal POC, or internal demo environment.
**Includes:** SSH, PostgreSQL, MySQL (RDS), MongoDB, Grafana, HTTPBin, AWS Console, Windows Desktop, Machine ID + MCP.
**Cost:** ~$5–10/day. Always destroy after the demo.

## Usage

```bash
cd profiles/windows-mongodb-ssh   # or cloud-native-apps / full-platform

# Required vars
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.0.0

# Optional overrides
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

terraform init
terraform apply

# After the demo
terraform destroy
```

After `apply`, Terraform prints a `connection_guide` output with all the relevant `tsh` commands pre-filled for your env/team labels.

## One-click deployment via GitHub Actions

Profiles can also be deployed without a local Terraform setup using the [`teleport-demo-deploy`](../../../.github/workflows/teleport-demo-deploy.yml) workflow. Go to **Actions → Deploy Teleport Demo → Run workflow** and fill in the form.

## Adding a New Profile

1. Create a directory under `profiles/` with a descriptive archetype name.
2. Write `main.tf` using modules from `../../modules/` directly — do **not** call the data-plane templates (they create their own VPCs; profiles share one).
3. Add `variables.tf` and `outputs.tf`. The `connection_guide` output is the SE's cheat sheet.
4. Add an entry to this README.
5. Run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` to generate the lock file.
