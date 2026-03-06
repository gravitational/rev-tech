# Application Access — Demo Panel

Deploys a Flask identity panel behind Teleport Application Access. The app reads the `Teleport-Jwt-Assertion` header and displays the logged-in user's Teleport identity, roles, and traits.

**Use case:** Show prospects what Teleport injects into every request — the user's identity flows through to internal apps with no extra login, no passwords, and full audit.

The Flask app lives in a standalone repo (set via `app_repo`) and is cloned at instance boot. This keeps application code separate from infrastructure.

---

## What It Deploys

- 1 EC2 instance (t3.micro) running Gunicorn + Flask app service + Teleport app and SSH agents
- Shared VPC/subnet/security group
- Dynamic Teleport app registration (`demo-panel-<env>`)

---

## Prerequisites

The demo app lives at [`https://github.com/tenaciousdlg/app-demo-panel`](https://github.com/tenaciousdlg/app-demo-panel) and is cloned automatically at instance boot. To use a custom app it must provide:
- `app.py` — Flask app that reads `Teleport-Jwt-Assertion` header
- `requirements.txt` — `flask>=3.0,<4` and `gunicorn>=22,<24`

---

## Deploy

```bash
tsh login --proxy=myorg.teleport.sh
eval $(tctl terraform env)

export TF_VAR_user=you@company.com
export TF_VAR_proxy_address=myorg.teleport.sh
export TF_VAR_teleport_version=18.6.4
export TF_VAR_env=dev
export TF_VAR_team=platform
export TF_VAR_region=us-east-2

cd data-plane/application-access-demo-panel
terraform init
terraform apply
```

Allow 2–3 minutes for the instance to boot, clone the app, and register.

---

## Access

```bash
tsh apps ls env=dev,team=platform   # demo-panel-dev
tsh apps login demo-panel-dev
```

Open `https://demo-panel-dev.<proxy>` in a browser. The panel shows:
- Username (from JWT `sub` claim)
- Roles assigned to the user
- Traits (group memberships, custom attributes)
- `DEMO_ENV` and `DEMO_TEAM` from the Terraform deployment

---

## Demo Points

- **No login page** — Teleport's App Service handles authentication and injects the JWT
- **Identity flows end-to-end** — the app sees the Teleport user without any separate auth integration
- **Any web app can do this** — just read the `Teleport-Jwt-Assertion` or `X-Forwarded-User` header
- **Session recorded** — every browser session is captured in the Teleport audit log

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
| `teleport_version` | Teleport version to install | **required** |
| `app_repo` | Git URL for the Flask demo panel app | `"https://github.com/tenaciousdlg/app-demo-panel"` |
| `env` | Environment label | **required** |
| `team` | Team label | `"platform"` |
| `region` | AWS region | **required** |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
