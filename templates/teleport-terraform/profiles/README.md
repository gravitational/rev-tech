# Profiles

One composable Terraform root. Every use case sits behind an `enable_*` flag, and a **preset** is just a `.tfvars` file that turns on a bundle of them — archetype demos and single-feature demos are the same mechanism.

All enabled use cases share one VPC, one state file, one `terraform destroy`.

## Usage

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env) # requires the preset Editor role or equivalent permissions to run

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com

cd profiles
terraform init
terraform apply -var-file=presets/dev-demo.tfvars

# after the demo
terraform destroy -var-file=presets/dev-demo.tfvars
```

Compose your own by combining flags: `terraform apply -var-file=presets/grafana.tfvars -var=enable_postgres=true`, or write a new preset file.

**Concurrent deployments** (e.g. postgres demo at 10am, full-platform at 2pm) need separate state — use workspaces: `terraform workspace new full-platform`.

## Presets

| Preset | Archetype / feature | Cost |
|---|---|---|
| `dev-demo` | Developer "day in the life" — Bob + access requests + session locking | ~$5–7/day |
| `full-platform` | All-up POC — every capability in one deployment | ~$8–12/day |
| `cloud-native-apps` | Modern cloud shop — Grafana, HTTPBin, RDS IAM auth, AWS Console | ~$3–5/day |
| `ssh`, `postgres`, `mysql`, `mongodb`, `cassandra`, `rds-mysql`, `grafana`, `httpbin`, `demo-panel`, `aws-console`, `windows`, `linux-desktop`, `mcp`, `ansible` | Single-feature demos (`linux-desktop` needs Teleport 19+) | ~$1–2/day each |

Costs assume the default `create_nat_gateway = false` (public subnet with public IPs, inbound blocked by the security group). A NAT gateway adds ~$1/day.

## Demo RBAC and the Bob persona

By default (`create_demo_rbac = true`) every deployment also creates the roles its narrative needs — prefixed with your username (e.g. `chris-dev-access`) so concurrent SEs on one cluster don't collide — plus a local `bob` user holding the dev role. Two one-time steps after `apply`, both printed in the `demo_user_setup` output:

1. **Activate bob:** `tctl users reset bob` prints a reset link (password + MFA), then `tsh login --user=bob --auth=local` (the `--auth=local` flag matters on SSO-default clusters).
2. **Approver role** (only when `enable_ssh_prod` is on): approving bob's prod request requires `<you>-reviewer` (`demo-reviewer` when `demo_rbac_role_prefix = ""`). Local admin: `tctl users update <you> --set-roles=<existing>,<you>-reviewer`. SSO user: grant via connector mapping or an access list. Staging requests skip the human when `auto_approve_reason` is set — policy approves them via an access monitoring rule.

Set `create_demo_rbac = false` if your cluster already runs the canonical role set from [`control-plane/cloud/3-rbac`](../control-plane/cloud/3-rbac/) — the request flow then uses `prod-readonly-access`.

## Demo flow: dev-demo (Developer Day in the Life)

Personas: **Bob** (local user, `<you>-dev-access` + `<you>-requester`) and **Alex** — played by you, with your own login plus `<you>-reviewer`.

1. **Bob logs in — sees only dev resources**
   ```bash
   tsh login --proxy=myorg.teleport.sh --user=bob --auth=local
   tsh ls          # dev-ssh-0, dev-ssh-1 — no prod-ssh-0
   ```
2. **SSH to a dev node** — `tsh ssh ec2-user@dev-ssh-0`. Teleport creates the host user on the fly; the session is recorded.
3. **Database access, no passwords** — `tsh db connect postgres-dev --db-user=writer --db-name=postgres` (short-lived client cert; same for mongodb-dev).
4. **App access with JWT** — `tsh apps login grafana-dev`, or open `https://httpbin-dev.<proxy>/headers` and point at `Teleport-Jwt-Assertion` / `X-Forwarded-User`.
5. **Bob requests prod access**
   ```bash
   tsh request create --roles=<you>-prod-access --reason="need to check prod logs"
   ```
6. **Alex approves** — Web UI, or `tsh request review <request-id> --approve --reason="ok"` (Slack notification requires the Access Request plugin on your cluster; the flow works without it).
7. **Bob's session gains prod** — `tsh ls` now shows `prod-ssh-0`; `tsh ssh ec2-user@prod-ssh-0`.
8. **Alex watches, then locks** — Web UI → Activity → Active Sessions → Join/Lock, or `tctl lock --user=bob --message="demo complete"`.
9. **Audit trail** — `tsh recordings ls`, and walk the audit log in the UI.
10. **Machine ID** — the Ansible host runs playbooks with tbot-issued short-lived certs (no SSH keys on disk); `tsh mcp config mcp-filesystem-dev` connects Claude/any MCP client through Teleport with a **read-only tool allowlist** — ask it to write a file and show the denial land in the audit log.

Allow 3–5 minutes after `apply` for instances to boot and register (`tsh ls`, `tsh db ls`, `tsh apps ls` to verify).

## Key variables

| Variable | Description | Default |
|---|---|---|
| `proxy_address` | Teleport proxy hostname (no scheme/port) | **required** |
| `user` | Your email — tagging, naming, role prefix | **required** |
| `enable_*` | One flag per use case — see variables.tf | all `false` |
| `profile_label` | Cost-attribution tag; presets set it | `"custom"` |
| `ssh_dev_count` | Dev SSH node count | `2` |
| `create_demo_rbac` | Demo roles + local demo user | `true` |
| `demo_user_name` | Local demo user name | `"bob"` |
| `extra_demo_user_names` | Extra demo users (one persona per demo workstation) | `[]` |
| `demo_rbac_role_prefix` | Role-name prefix; `""` = canonical unprefixed names (dedicated clusters) | your username |
| `auto_approve_reason` | Exact request reason that policy-approves `staging-access` requests | `null` (off) |
| `request_max_duration` | Max JIT window for approved access requests | `1h` |
| `env` / `prod_env` / `team` | Labels driving RBAC | `dev` / `prod` / `platform` |
| `region` | AWS region | `us-east-2` |
| `create_nat_gateway` | Private subnet + NAT (~$1/day) | `false` |

Agents install the cluster's current version and stay up to date via [Agent Managed Updates](https://goteleport.com/docs/upgrading/agent-managed-updates/) — there is no version knob.

## Adding a preset

Create `presets/<name>.tfvars` setting `profile_label = "<name>"` and the `enable_*` flags for the story, then add a row to the table above. New use cases: add a module block behind a new flag in `main.tf` (compose from `../modules/`), a `%{ if }` section in the `connection_guide` output, and a single-feature preset.
