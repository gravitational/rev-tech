# Application Access — HTTPBin

Deploys an HTTPBin instance on EC2 and registers it with Teleport Application Access.

**Use case:** Show exactly what Teleport injects into every proxied HTTP request — the JWT header, forwarded user, and identity claims — without needing a custom app.

Mirrors the official [Protect a Web Application](https://goteleport.com/docs/enroll-resources/application-access/getting-started/) guide.

---

## What It Deploys

- 1 EC2 instance running HTTPBin on Docker
- Teleport agent with `app_service` and `ssh_service`
- Dynamic app registration (`httpbin-<env>`) with `env` + `team` labels

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

cd data-plane/application-access-httpbin
terraform init
terraform apply
```

Allow 2–3 minutes for the instance to boot and register.

---

## Access

```bash
tsh apps ls env=dev,team=platform   # httpbin-dev
tsh apps login httpbin-dev
```

Open `https://httpbin-dev.<proxy>/headers` in a browser. The JSON response shows all headers Teleport injects, including `Teleport-Jwt-Assertion`.

---

## Demo Points

- **Header inspection** — navigate to `/headers` to see every header Teleport injects, including the signed `Teleport-Jwt-Assertion` JWT carrying the user's identity
- **No login page** — Teleport's App Service authenticates the user before any request reaches HTTPBin
- **Proxy-only exposure** — HTTPBin is never reachable directly; the EC2 security group blocks all inbound traffic except from the Teleport agent
- **Session recording** — every browser session is captured in the Teleport audit log and replayable with `tsh recordings ls`
- **Drop-in replacement** — swap HTTPBin for any internal web app; the Teleport integration is identical

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
