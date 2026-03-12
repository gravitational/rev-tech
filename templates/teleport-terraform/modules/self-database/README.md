# Module: self-database

Provisions a self-hosted database on EC2 with Teleport Database Access. A single parameterized module replaces separate `self-postgres`, `self-mysql`, `self-mongodb`, and `self-cassandra` modules.

**Supported engines:** `postgres`, `mysql`, `mongodb`, `cassandra`

For each engine, the module:
- Generates a private CA and TLS certificate (Terraform-managed, in-memory)
- Installs and configures the database on Amazon Linux 2023
- Installs and configures the Teleport DB agent
- Registers the Teleport provision token
- Outputs the CA cert chain for use by the `dynamic-registration` module

---

## Usage

```hcl
data "http" "teleport_db_ca" {
  url = "https://${var.proxy_address}/webapi/auth/export?type=db-client"
}

module "postgres" {
  source = "../../modules/self-database"

  db_type          = "postgres"
  env              = var.env
  team             = var.team
  user             = var.user
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  teleport_db_ca   = data.http.teleport_db_ca.response_body
  ami_id           = data.aws_ami.linux.id
  instance_type    = "t3.small"
  subnet_id        = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}

module "postgres_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "database"
  name          = "postgres-${var.env}"
  protocol      = "postgres"
  uri           = "localhost:5432"
  ca_cert_chain = module.postgres.ca_cert
  labels        = { env = var.env, team = var.team }
}
```

To deploy multiple databases in the same profile, call the module multiple times with different `db_type` values — each gets its own EC2 instance:

```hcl
module "postgres" { source = "../../modules/self-database"; db_type = "postgres"; ... }
module "mysql"    { source = "../../modules/self-database"; db_type = "mysql";    ... }
module "mongodb"  { source = "../../modules/self-database"; db_type = "mongodb";  ... }
```

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `db_type` | Database engine: `postgres`, `mysql`, `mongodb`, or `cassandra` | **required** |
| `env` | Environment label (e.g., `dev`, `prod`) | **required** |
| `user` | Tag value for resource creator | **required** |
| `proxy_address` | Teleport proxy hostname (no `https://`, no port) | **required** |
| `teleport_version` | Teleport version to install | **required** |
| `teleport_db_ca` | Teleport DB CA cert from `/webapi/auth/export?type=db-client` | **required** |
| `ami_id` | AMI ID for the EC2 instance (Amazon Linux 2023 recommended) | **required** |
| `instance_type` | EC2 instance type | **required** |
| `subnet_id` | Subnet to launch the instance in | **required** |
| `security_group_ids` | Security group IDs for the instance | **required** |
| `db_hostname` | Hostname for the DB server (used in TLS cert SAN) | `"db.example.internal"` |
| `team` | Team label | `"platform"` |

---

## Outputs

| Output | Description |
|---|---|
| `ca_cert` | PEM-encoded CA certificate chain — pass to `dynamic-registration` as `ca_cert_chain` |

---

## Default Ports

| Engine | Port |
|---|---|
| PostgreSQL | 5432 |
| MySQL | 3306 |
| MongoDB | 27017 |
| Cassandra | 9042 |

Pass `uri = "localhost:<port>"` to `dynamic-registration` to match.

---

## Database Users

Each engine is configured with demo users for connecting through Teleport:

| Engine | Users |
|---|---|
| PostgreSQL | `reader`, `writer` |
| MySQL | `alice`, `bob` |
| MongoDB | `reader`, `writer` |
| Cassandra | `teleport` |

The `--db-user` flag in `tsh db login` maps to these. Teleport issues a short-lived client cert with the CN matching the DB user — no passwords are stored anywhere.

---

## Connection Examples

```bash
# PostgreSQL
tsh db login postgres-dev --db-user=writer --db-name=postgres
tsh db connect postgres-dev

# MySQL
tsh db login mysql-dev --db-user=alice --db-name=mysql
tsh db connect mysql-dev

# MongoDB
tsh db login mongodb-dev --db-user=writer
tsh db connect mongodb-dev

# Cassandra
tsh db login cassandra-dev --db-user=teleport
tsh db connect cassandra-dev
```
