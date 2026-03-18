# Profile: dev-demo — Developer Day in the Life

**Archetype:** Any engineering org evaluating Teleport for day-to-day developer access.

Use this for focused POCs or live demos where you walk through a realistic "developer day in the life" with two personas — Bob (a developer) and engineer (a platform engineer).

**Cost:** ~$5–7/day. Destroy after the demo.

---

## What It Deploys

| Resource | Count | Type | Purpose |
|---|---|---|---|
| Dev SSH nodes | 2 | t3.micro | Bob's normal work environment |
| Prod SSH node | 1 | t3.micro | Behind access request — Bob can't see it without approval |
| PostgreSQL (dev) | 1 | t3.small | Self-hosted, cert auth, no passwords |
| MongoDB (dev) | 1 | t3.small | Self-hosted, cert auth, no passwords |
| Grafana | 1 | t3.small | App Access + JWT identity injection |
| HTTPBin | 1 | t3.micro | Shows raw Teleport-injected headers |
| Windows Server | 1 | t3.medium | Desktop Access target |
| Desktop Service | 1 | t3.small | Linux RDP proxy for the Windows host |
| MCP stdio host | 1 | t3.small | AI/Claude integration via MCP |
| Ansible host | 1 | t3.small | Machine ID bot + Ansible automation (baked into module) |
| NAT Gateway | 1 | — | ~$1.20/day fixed |

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_user=you@company.com
export TF_VAR_teleport_version=18.6.4
export TF_VAR_region=us-east-2          # optional, default: us-east-2
export TF_VAR_env=dev                   # optional, default: dev
export TF_VAR_team=platform             # optional, default: platform

cd profiles/dev-demo
terraform init
terraform apply
```

Allow 3–5 minutes for all instances to boot and register. Then verify:

```bash
tsh ls                              # dev nodes appear
tsh db ls                           # postgres-dev, mongodb-dev
tsh apps ls                         # grafana-dev, httpbin-dev, mcp-filesystem-dev
```

---

## Demo Flow

### Personas

| Persona | Identity | Groups | Access |
|---|---|---|---|
| Bob | `bob@...` | devs | Dev-labeled SSH, databases, apps — **no prod** |
| engineer | `engineer@...` | engineers | All dev resources + prod (standing access) + approver |

### Step-by-Step

**1. Bob logs in — sees only dev resources**

```bash
tsh login --proxy=myorg.teleport.sh --user=bob
tsh ls                              # dev-ssh-0, dev-ssh-1 only — no prod-server
tsh db ls                           # postgres-dev, mongodb-dev
tsh apps ls                         # grafana-dev, httpbin-dev
```

**2. SSH to a dev node — dynamic host user creation**

```bash
tsh ssh ec2-user@dev-ssh-0
# Teleport created the ec2-user account on the fly — no pre-provisioning
# Session is recorded; run `w` or `who` to see the audit user
```

**3. Database access — no passwords**

```bash
# PostgreSQL
tsh db login postgres-dev --db-user=writer --db-name=postgres
tsh db connect postgres-dev
# psql prompt — connected via short-lived cert, no password ever touched

# MongoDB
tsh db login mongodb-dev --db-user=writer
tsh db connect mongodb-dev
# mongosh prompt
```

**4. App access — Grafana with JWT**

```bash
tsh apps login grafana-dev
tsh apps config grafana-dev
# or open https://grafana-dev.<proxy> in browser — logged in automatically
```

**5. HTTPBin — show injected headers**

Open `https://httpbin-dev.<proxy>/headers` in browser. Look for:
- `Teleport-Jwt-Assertion` — signed JWT with Bob's identity
- `X-Forwarded-User` — Bob's username

**6. Bob submits an access request**

```bash
tsh request create --roles=prod-readonly-access --reason="need to check prod logs"
# Bob gets a request ID
```

**7. engineer approves (Slack notification or web UI)**

```bash
# engineer reviews and approves
tsh request review <request-id> --approve --reason="approved for the session"
```

**8. Bob's session gets prod access**

```bash
# In Bob's terminal (no re-login needed)
tsh ls                              # prod-server now appears
tsh ssh ec2-user@prod-server        # Bob is in
```

**9. engineer watches the live session — then locks it**

In the Teleport Web UI: **Activity → Active Sessions** → find Bob's prod session → **Join** or **Lock**.

```bash
# Or lock via CLI
tsh request lock --user=bob --reason="demo complete"
```

**10. Ansible Machine ID demo**

```bash
tsh ls env=dev,team=platform
tsh ssh ec2-user@<ansible-host>

# On the ansible host:
cd ansible/
# Edit hosts with Teleport node hostnames from: tsh ls --format=json | jq -r '.[].spec.hostname'
ansible-playbook -i hosts playbook.yaml
# Ansible authenticates via tbot short-lived cert — no SSH keys on disk
```

**11. MCP / AI integration**

```bash
tsh mcp ls
tsh mcp config mcp-filesystem-dev
# Paste the output into Claude Desktop, Cursor, or any MCP client
# Claude can now run tools against live infrastructure through Teleport
```

**12. Windows Desktop Access**

No CLI — web UI only. Open `https://<proxy>` → **Windows Desktops** → click **Connect**. Browser-based RDP, full session recording.

---

## Teardown

```bash
terraform destroy
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `proxy_address` | Teleport proxy hostname (no https, no port) | **required** |
| `user` | Your email — used for tagging and resource naming | **required** |
| `teleport_version` | Teleport version to install on all nodes | **required** |
| `env` | Environment label for dev resources | `"dev"` |
| `prod_env` | Environment label for the prod SSH node (access request target) | `"prod"` |
| `team` | Team label for Teleport RBAC | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
