# Application Access — Grafana

Deploys a self-hosted Grafana container on EC2 and registers it with Teleport Application Access using JWT-based single sign-on.

**Use case:** Show how Teleport authenticates users into internal web apps — no separate login, no VPN, full audit trail.

Mirrors the official [Protect a Web Application](https://goteleport.com/docs/enroll-resources/application-access/getting-started/) and [JWT Tokens with App Access](https://goteleport.com/docs/enroll-resources/application-access/jwt/introduction/) guides.

---

## What It Deploys

- 1 EC2 instance running Grafana on Docker
- Teleport agent with `app_service` and `ssh_service`
- Dynamic app registration (`grafana-<env>`) with `env` + `team` labels

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

cd data-plane/application-access-grafana
terraform init
terraform apply
```

Allow 2–3 minutes for the instance to boot and register.

---

## Access

```bash
tsh apps ls env=dev,team=platform   # grafana-dev
tsh apps login grafana-dev
```

Open `https://grafana-dev.<proxy>` in a browser. Grafana logs you in automatically using the Teleport-injected JWT — no Grafana password prompt.

---

## Demo Points

- **No separate login** — Teleport injects a signed JWT; Grafana's JWT auth provider accepts it directly — users land in the dashboard without a second credential
- **Identity-aware sessions** — the Grafana session is tied to the Teleport user's identity and roles, not a shared service account
- **Zero direct exposure** — Grafana's port is never open to the internet; all access flows through the Teleport proxy
- **Session recording** — every Grafana browser session is captured in the Teleport audit log and replayable with `tsh recordings ls`

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
| `env` | Environment label | **required** |
| `team` | Team label | `"platform"` |
| `region` | AWS region | **required** |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
