# Database Access — Cassandra (Self-Managed)

Deploys a self-hosted Apache Cassandra instance on EC2 with Teleport Database Access. Teleport issues short-lived TLS certificates for each connection — no passwords, no shared credentials.

This template uses the consolidated `self-database` module with `db_type = "cassandra"`.

**Tested:** ✅ Confirmed working — `writer@cqlsh>` prompt via `tsh db connect`.

---

## What It Deploys

- 1 EC2 instance (t3.medium) running Cassandra 4.x + Teleport DB agent
- Terraform-managed private CA and TLS certificate
- Shared VPC/subnet/security group
- Dynamic Teleport database registration (`cassandra-<env>`)

> Cassandra uses t3.medium (vs. t3.small for other engines) — the JVM heap requires more memory.

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

cd data-plane/database-access-cassandra-self-managed
terraform init
terraform apply
```

Allow 3–5 minutes. Cassandra startup takes longer than other engines due to JVM initialization.

---

## Access

```bash
tsh db ls env=dev,team=platform             # cassandra-dev
tsh db login cassandra-dev --db-user=teleport
tsh db connect cassandra-dev
# Connected to Test Cluster at <...>.
# [cqlsh 6.x.x | Cassandra 4.x.x | CQL spec 3.4.7 | Native protocol v5]
# writer@cqlsh>
```

---

## Demo Points

- **Certificate-based auth** — Teleport generates a client cert with CN=teleport; Cassandra validates against the custom CA
- **No passwords in the chain** — no DB passwords stored in Teleport, Terraform, or the application
- **Short-lived certs** — the cert expires when the Teleport session expires
- **Full audit** — every query session is captured in the Teleport audit log

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
| `env` | Environment label | `"dev"` |
| `team` | Team label | `"platform"` |
| `region` | AWS region | `"us-east-2"` |
| `cidr_vpc` | VPC CIDR | `"10.0.0.0/16"` |
| `cidr_subnet` | Private subnet CIDR | `"10.0.1.0/24"` |
| `cidr_public_subnet` | Public subnet CIDR (NAT) | `"10.0.0.0/24"` |
