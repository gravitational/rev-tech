# Database Access — MongoDB (Self-Managed)

Deploys a self-hosted MongoDB instance on EC2 with mutual TLS and registers it with Teleport Database Access.

**Use case:** Show passwordless, certificate-based database access with full session recording for a self-managed NoSQL database.

Mirrors the official [Self-Hosted MongoDB guide](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/mongodb-self-hosted/).

---

## What It Deploys

- 1 EC2 instance running MongoDB Community Edition 8.0 on Amazon Linux 2023
- Custom CA and server TLS certificate for mTLS connectivity
- Teleport agent with `db_service` and `ssh_service`
- Dynamic database registration (`mongodb-<env>`) with `env` + `team` labels

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

cd data-plane/database-access-mongodb-self-managed
terraform init
terraform apply
```

Allow 3–5 minutes for the instance to boot, configure MongoDB, and register.

---

## Access

```bash
tsh db ls env=dev,team=platform        # mongodb-dev
tsh db connect mongodb-dev --db-user=reader --db-name=dev
```

To connect as a writer:

```bash
tsh db connect mongodb-dev --db-user=writer --db-name=dev
```

---

## Demo Points

- **No database password** — Teleport issues short-lived X.509 certificates; MongoDB validates the Teleport DB CA, not a password
- **Role-based access** — `reader` and `writer` database users are mapped from Teleport roles using certificate CN matching; the user never sees a credential
- **Session recording** — every query is captured in the Teleport audit log tied to the Teleport username, not a shared DB account
- **Credential-free** — certificates are generated on-demand and expire when the session ends; there is nothing to rotate or leak

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
