# Database Access — MySQL (Self-Managed)

Deploys a self-hosted MySQL instance on EC2 with mutual TLS and registers it with Teleport Database Access.

**Use case:** Show passwordless, certificate-based database access with full session recording for a self-managed relational database.

Mirrors the official [Self-Hosted MySQL guide](https://goteleport.com/docs/enroll-resources/database-access/enroll-self-hosted-databases/mysql-self-hosted/).

---

## What It Deploys

- 1 EC2 instance running MySQL (MariaDB) on Ubuntu 22.04
- Custom CA and server TLS certificate for mTLS connectivity
- Teleport agent with `db_service` and `ssh_service`
- Dynamic database registration (`mysql-<env>`) with `env` + `team` labels

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

cd data-plane/database-access-mysql-self-managed
terraform init
terraform apply
```

Allow 3–5 minutes for the instance to boot, configure MySQL, and register.

---

## Access

```bash
tsh db ls env=dev,team=platform        # mysql-dev
tsh db connect mysql-dev --db-user=alice
```

To connect as a different user:

```bash
tsh db connect mysql-dev --db-user=bob
```

---

## Demo Points

- **No database password** — Teleport issues short-lived X.509 certificates; MySQL validates the Teleport DB CA, not a password
- **Role-based access** — `alice` and `bob` database users are mapped from Teleport roles using certificate CN matching; the user never sees a credential
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
