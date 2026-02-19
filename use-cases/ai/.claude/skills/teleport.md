# teleport -- Teleport Server Daemon

The `teleport` binary is the main Teleport server daemon that provides unified identity for humans, machines, and AI. It runs as one or more services: auth server (cluster CA and identity authority), proxy (client entry point and web UI), SSH node, application proxy, database proxy, Kubernetes access, and discovery agent. A single instance can run multiple roles simultaneously.

**Binary:** `teleport` (Teleport v18+)
**Default config:** `/etc/teleport.yaml`
**Documentation:** <https://goteleport.com/docs/reference/cli/teleport/>

---

## Quick Reference

### Start Services

```bash
# Start with default roles (auth, proxy, node)
teleport start

# Start with specific roles
teleport start --roles=proxy,auth
teleport start --roles=node --auth-server=auth.example.com:3025 --token=invite-token

# Start with config file
teleport start -c /etc/teleport.yaml

# Start with debug logging
teleport start --debug

# Start in FIPS mode
teleport start --fips

# Start with bootstrap resources (first run only)
teleport start --bootstrap=/path/to/resources.yaml

# Start with resources applied on every startup
teleport start --apply-on-startup=/path/to/resources.yaml

# Start with diagnostic endpoint
teleport start --diag-addr=0.0.0.0:3434
```

### Generate Configuration

```bash
# Generate a basic config to stdout
teleport configure

# Generate config to a file
teleport configure -o file:///etc/teleport.yaml

# Generate config with cluster name and ACME
teleport configure --cluster-name=example.com --acme --acme-email=admin@example.com

# Generate config with TLS certificates
teleport configure --cluster-name=example.com \
  --cert-file=/etc/letsencrypt/live/example.com/fullchain.pem \
  --key-file=/etc/letsencrypt/live/example.com/privkey.pem

# Generate config for a node joining a cluster
teleport configure --roles=node --token=invite-token --auth-server=auth.example.com:3025

# Generate config for an app service
teleport configure --roles=app --app-name=grafana --app-uri=http://localhost:3000 \
  --token=invite-token --auth-server=auth.example.com:3025

# Test/validate a configuration file
teleport configure --test=/etc/teleport.yaml

# Generate node-specific config
teleport node configure --proxy=proxy.example.com:443 --token=node-token \
  --node-name=web-server --labels=env=prod,team=backend -o file:///etc/teleport.yaml
```

### Start Individual Services

```bash
# Start application proxy service
teleport app start --name=grafana --uri=http://localhost:3000 \
  --auth-server=auth.example.com:3025 --token=app-token

# Start database proxy service
teleport db start --name=my-postgres --protocol=postgres --uri=localhost:5432 \
  --auth-server=auth.example.com:3025 --token=db-token

# Join an OpenSSH server to the cluster
teleport join openssh --proxy-server=proxy.example.com:443 \
  --token=openssh-token --join-method=token
```

### Utility Commands

```bash
# Print version
teleport version

# Print SSH session status
teleport status

# Install systemd unit file
teleport install systemd -o file:///etc/systemd/system/teleport.service

# Identify TPM
teleport tpm identify
```

---

## teleport start

Starts the Teleport service. By default runs auth, proxy, and node services.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--config` | `-c` | Path to configuration file | `/etc/teleport.yaml` |
| `--roles` | `-r` | Comma-separated service roles: proxy, node, auth, app, db | `node,proxy,auth` |
| `--debug` | `-d` | Enable verbose logging to stderr | `false` |
| `--token` | | Invitation token or path to file with token value | |
| `--auth-server` | | Address of the auth server (repeatable) | `127.0.0.1:3025` |
| `--listen-ip` | `-l` | IP address to bind to | `0.0.0.0` |
| `--advertise-ip` | | IP to advertise to clients if running behind NAT | |
| `--nodename` | | Name of this node | hostname |
| `--labels` | | Comma-separated labels (e.g., `env=dev,app=web`) | |
| `--ca-pin` | | CA pin to validate the Auth Server (repeatable) | |
| `--pid-file` | | Full path to the PID file | |
| `--diag-addr` | | Start diagnostic prometheus and healthz endpoint | |
| `--bootstrap` | | Path to YAML file with bootstrap resources (ignored if already initialized) | |
| `--apply-on-startup` | | Path to YAML file with resources to apply on startup | |
| `--fips` | | Start in FedRAMP/FIPS 140 mode | `false` |
| `--insecure` | | Disable certificate validation | `false` |
| `--insecure-no-tls` | | Disable TLS for the web socket | `false` |
| `--permit-user-env` | | Enable reading of `~/.tsh/environment` when creating a session | `false` |
| `--skip-version-check` | | Skip version checking between server and client | `false` |
| `--no-debug-service` | | Disable the debug service | `false` |

### Apply-on-Startup Resources

The `--apply-on-startup` flag supports these resource types:

- `cluster_auth_preference`
- `bot`
- `role`
- `user`
- `token`
- `cluster_networking_config`

```yaml
# Example: /etc/teleport-resources.yaml
kind: role
version: v7
metadata:
  name: access
spec:
  allow:
    logins: [root, ubuntu]
    node_labels:
      '*': '*'
---
kind: token
version: v2
metadata:
  name: node-token
spec:
  roles: [Node]
  join_method: token
```

```bash
teleport start --apply-on-startup=/etc/teleport-resources.yaml
```

---

## teleport configure

Generate a simple config file to get started.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--cluster-name` | | Unique cluster name (e.g., example.com) | |
| `--output` | `-o` | Output destination: `stdout`, `file`, or `file:///path` | `stdout` |
| `--acme` | | Get automatic certificate from Let's Encrypt using ACME | `false` |
| `--acme-email` | | Email to receive updates from Let's Encrypt | |
| `--test` | | Path to a configuration file to test/validate | |
| `--version` | | Teleport configuration version | `v3` |
| `--public-addr` | | Hostport the proxy advertises for the HTTP endpoint | |
| `--cert-file` | | Path to a TLS certificate file for the proxy | |
| `--key-file` | | Path to a TLS key file for the proxy | |
| `--data-dir` | | Path to directory where Teleport keeps data | `/var/lib/teleport` |
| `--token` | | Invitation token or path to file with token value | |
| `--join-method` | | Join method | `token` |
| `--roles` | | Comma-separated list of roles | |
| `--auth-server` | | Address of the auth server | |
| `--proxy` | | Address of the proxy | |
| `--app-name` | | Name of the application to start when using app role | |
| `--app-uri` | | Internal address of the application to proxy | |
| `--mcp-demo-server` | | Enable Teleport demo MCP server | `false` |
| `--node-name` | | Name for the Teleport node | |
| `--node-labels` | | Comma-separated list of labels for new nodes | |

### Examples

```bash
# Minimal cluster config
teleport configure --cluster-name=example.com -o file:///etc/teleport.yaml

# Config with Let's Encrypt
teleport configure --cluster-name=example.com \
  --acme --acme-email=admin@example.com \
  -o file:///etc/teleport.yaml

# Config for a node joining via IAM
teleport configure --roles=node \
  --join-method=iam \
  --auth-server=auth.example.com:3025 \
  -o file:///etc/teleport.yaml

# Config for an app service
teleport configure --roles=app \
  --app-name=grafana --app-uri=http://localhost:3000 \
  --token=app-token --auth-server=auth.example.com:3025 \
  -o file:///etc/teleport.yaml

# Validate an existing config
teleport configure --test=/etc/teleport.yaml
```

---

## teleport node configure

Generate a configuration file for an SSH node.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--cluster-name` | | Unique cluster name | |
| `--output` | `-o` | Output destination | `stdout` |
| `--version` | | Teleport configuration version | `v3` |
| `--public-addr` | | Hostport for the SSH endpoint | |
| `--data-dir` | | Data directory | `/var/lib/teleport` |
| `--token` | | Invitation token or path to file | |
| `--auth-server` | | Address of the auth server | |
| `--proxy` | | Address of the proxy server | |
| `--labels` | | Comma-separated list of labels | |
| `--ca-pin` | | SKPI hashes for CA verification (comma-separated) | |
| `--join-method` | | Join method | `token` |
| `--node-name` | | Name for the Teleport node | |
| `--silent` | | Suppress user hint message | `false` |
| `--azure-client-id` | | Client ID of the managed identity (azure join method) | |

### Examples

```bash
# Generate node config joining via proxy
teleport node configure \
  --proxy=proxy.example.com:443 \
  --token=node-token \
  --node-name=web-01 \
  --labels=env=prod,team=backend \
  -o file:///etc/teleport.yaml

# Generate node config with CA pin
teleport node configure \
  --auth-server=auth.example.com:3025 \
  --token=node-token \
  --ca-pin=sha256:abcdef1234567890 \
  -o file:///etc/teleport.yaml

# Generate node config for Azure join
teleport node configure \
  --proxy=proxy.example.com:443 \
  --join-method=azure \
  --azure-client-id=<managed-identity-client-id> \
  -o file:///etc/teleport.yaml
```

---

## teleport app start

Start application proxy service.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--name` | | Name of the application to start | |
| `--uri` | | Internal address of the application to proxy | |
| `--cloud` | | Cloud API to proxy: AWS, Azure, or GCP | |
| `--public-addr` | | Public address of the application | |
| `--labels` | | Comma-separated list of labels | |
| `--debug` | `-d` | Enable verbose logging to stderr | `false` |
| `--auth-server` | | Address of the auth server (repeatable) | `127.0.0.1:3025` |
| `--token` | | Invitation token or path to file | |
| `--ca-pin` | | CA pin to validate the auth server (repeatable) | |
| `--config` | `-c` | Path to a configuration file | `/etc/teleport.yaml` |
| `--pid-file` | | Full path to the PID file | |
| `--diag-addr` | | Start diagnostic prometheus and healthz endpoint | |
| `--fips` | | Start in FedRAMP/FIPS 140 mode | `false` |
| `--insecure` | | Disable certificate validation | `false` |
| `--skip-version-check` | | Skip version checking | `false` |
| `--no-debug-service` | | Disable the debug service | `false` |
| `--mcp-demo-server` | | Enable Teleport demo MCP server | `false` |

### Examples

```bash
# Start a web application proxy
teleport app start --name=grafana --uri=http://localhost:3000 \
  --auth-server=auth.example.com:3025 --token=app-token \
  --labels=env=prod,team=monitoring

# Start an AWS cloud proxy
teleport app start --name=aws-console --cloud=AWS \
  --auth-server=auth.example.com:3025 --token=app-token

# Start an Azure cloud proxy
teleport app start --name=azure-portal --cloud=Azure \
  --auth-server=auth.example.com:3025 --token=app-token

# Start a GCP cloud proxy
teleport app start --name=gcp-console --cloud=GCP \
  --auth-server=auth.example.com:3025 --token=app-token

# Start with MCP demo server
teleport app start --name=mcp-app --uri=http://localhost:8080 \
  --auth-server=auth.example.com:3025 --token=app-token \
  --mcp-demo-server

# Start with diagnostic endpoint
teleport app start --name=myapp --uri=http://localhost:8080 \
  --auth-server=auth.example.com:3025 --token=app-token \
  --diag-addr=0.0.0.0:3434
```

---

## teleport db start

Start database proxy service.

### Core Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--name` | | Name of the proxied database | |
| `--description` | | Description of the proxied database | |
| `--protocol` | | Database protocol (see supported protocols below) | |
| `--uri` | | Address the proxied database is reachable at | |
| `--ca-cert` | | Database CA certificate path | |
| `--labels` | | Comma-separated list of labels | |
| `--debug` | `-d` | Enable verbose logging to stderr | `false` |
| `--auth-server` | | Address of the auth server (repeatable) | `127.0.0.1:3025` |
| `--token` | | Invitation token or path to file | |
| `--ca-pin` | | CA pin to validate the auth server (repeatable) | |
| `--config` | `-c` | Path to a configuration file | `/etc/teleport.yaml` |
| `--pid-file` | | Full path to the PID file | |
| `--diag-addr` | | Start diagnostic prometheus and healthz endpoint | |
| `--fips` | | Start in FedRAMP/FIPS 140 mode | `false` |
| `--insecure` | | Disable certificate validation | `false` |
| `--skip-version-check` | | Skip version checking | `false` |
| `--no-debug-service` | | Disable the debug service | `false` |

### AWS-Specific Flags

| Flag | Description |
|------|-------------|
| `--aws-region` | AWS region for RDS/Aurora/Redshift/ElastiCache/MemoryDB |
| `--aws-account-id` | AWS Account ID (Keyspaces/DynamoDB) |
| `--aws-assume-role-arn` | Optional AWS IAM role to assume |
| `--aws-external-id` | Optional AWS external ID for assuming roles |
| `--aws-redshift-cluster-id` | Redshift cluster identifier |
| `--aws-rds-instance-id` | RDS instance identifier |
| `--aws-rds-cluster-id` | Aurora cluster identifier |
| `--aws-session-tags` | STS tags (DynamoDB only) |

### GCP-Specific Flags

| Flag | Description |
|------|-------------|
| `--gcp-project-id` | GCP Cloud SQL project identifier |
| `--gcp-instance-id` | GCP Cloud SQL instance identifier |
| `--gcp-alloydb-endpoint-type` | AlloyDB endpoint type: public, private, psc |

### Active Directory / Kerberos Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--ad-keytab-file` | Kerberos keytab file (SQL Server) | |
| `--ad-krb5-file` | Kerberos krb5.conf file (SQL Server) | `/etc/krb5.conf` |
| `--ad-domain` | Active Directory domain (SQL Server) | |
| `--ad-spn` | Service Principal Name (SQL Server) | |

### Supported Database Protocols

`postgres`, `mysql`, `mongodb`, `oracle`, `cockroachdb`, `redis`, `snowflake`, `sqlserver`, `cassandra`, `elasticsearch`, `opensearch`, `dynamodb`, `clickhouse`, `clickhouse-http`, `spanner`

### Examples

```bash
# Start a PostgreSQL database proxy
teleport db start --name=my-postgres --protocol=postgres \
  --uri=postgres.internal:5432 \
  --auth-server=auth.example.com:3025 --token=db-token \
  --labels=env=prod,team=backend

# Start a MySQL database proxy
teleport db start --name=my-mysql --protocol=mysql \
  --uri=mysql.internal:3306 \
  --auth-server=auth.example.com:3025 --token=db-token

# Start an AWS RDS proxy
teleport db start --name=my-rds --protocol=postgres \
  --uri=my-rds-instance.abc123.us-east-1.rds.amazonaws.com:5432 \
  --aws-region=us-east-1 --aws-rds-instance-id=my-rds-instance \
  --auth-server=auth.example.com:3025 --token=db-token

# Start a GCP Cloud SQL proxy
teleport db start --name=my-cloudsql --protocol=postgres \
  --uri=my-instance:5432 \
  --gcp-project-id=my-project --gcp-instance-id=my-instance \
  --auth-server=auth.example.com:3025 --token=db-token

# Start a SQL Server proxy with Kerberos auth
teleport db start --name=my-sqlserver --protocol=sqlserver \
  --uri=sqlserver.internal:1433 \
  --ad-domain=CORP.EXAMPLE.COM --ad-spn=MSSQLSvc/sqlserver.internal:1433 \
  --ad-keytab-file=/etc/krb5.keytab \
  --auth-server=auth.example.com:3025 --token=db-token

# Start a MongoDB proxy
teleport db start --name=my-mongo --protocol=mongodb \
  --uri=mongo.internal:27017 --ca-cert=/path/to/mongo-ca.pem \
  --auth-server=auth.example.com:3025 --token=db-token

# Start a DynamoDB proxy
teleport db start --name=my-dynamo --protocol=dynamodb \
  --uri=dynamodb.us-east-1.amazonaws.com \
  --aws-region=us-east-1 --aws-account-id=123456789012 \
  --auth-server=auth.example.com:3025 --token=db-token
```

---

## teleport db configure

Bootstrap database service configuration and cloud permissions.

### teleport db configure create

Creates a sample Database Service configuration.

#### Core Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--output` | `-o` | Output destination | `stdout` |
| `--proxy` | | Teleport proxy address | `0.0.0.0:3080` |
| `--token` | | Invitation token or path to file | `/tmp/token` |
| `--name` | | Name of the proxied database | |
| `--protocol` | | Database protocol | |
| `--uri` | | Address the proxied database is reachable at | |
| `--labels` | | Comma-separated labels | |
| `--ca-pin` | | CA pin (repeatable) | |
| `--ca-cert-file` | | Database CA certificate path | |
| `--dynamic-resources-labels` | | Labels to match dynamic resources (repeatable) | |
| `--trust-system-cert-pool` | | Trust system CAs for self-hosted databases | `false` |

#### AWS Discovery Flags

| Flag | Description |
|------|-------------|
| `--rds-discovery` | AWS regions for RDS/Aurora auto-discovery (repeatable) |
| `--rdsproxy-discovery` | AWS regions for RDS Proxy discovery (repeatable) |
| `--redshift-discovery` | AWS regions for Redshift discovery (repeatable) |
| `--redshift-serverless-discovery` | AWS regions for Redshift Serverless discovery (repeatable) |
| `--elasticache-discovery` | AWS regions for ElastiCache Valkey/Redis discovery (repeatable) |
| `--elasticache-serverless-discovery` | AWS regions for ElastiCache Serverless discovery (repeatable) |
| `--memorydb-discovery` | AWS regions for MemoryDB discovery (repeatable) |
| `--opensearch-discovery` | AWS regions for OpenSearch discovery (repeatable) |
| `--aws-tags` | AWS resource tags to match (e.g., `env=dev,dept=it`) |
| `--aws-region` | AWS region |
| `--aws-account-id` | AWS Account ID |
| `--aws-assume-role-arn` | AWS IAM role to assume |
| `--aws-external-id` | AWS external ID |
| `--aws-redshift-cluster-id` | Redshift cluster identifier |
| `--aws-rds-cluster-id` | RDS Aurora cluster identifier |
| `--aws-rds-instance-id` | RDS instance identifier |
| `--aws-elasticache-group-id` | ElastiCache replication group identifier |
| `--aws-elasticache-serverless-cache-name` | ElastiCache Serverless cache name |
| `--aws-memorydb-cluster-name` | MemoryDB cluster name |

#### Azure Discovery Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--azure-mysql-discovery` | Azure regions for MySQL discovery (repeatable) | |
| `--azure-postgres-discovery` | Azure regions for PostgreSQL discovery (repeatable) | |
| `--azure-redis-discovery` | Azure regions for Azure Cache For Redis discovery (repeatable) | |
| `--azure-sqlserver-discovery` | Azure regions for Azure SQL discovery (repeatable) | |
| `--azure-subscription` | Azure subscription IDs (repeatable) | `*` |
| `--azure-resource-group` | Azure resource groups (repeatable) | `*` |
| `--azure-tags` | Azure resource tags to match | |

#### GCP Flags

| Flag | Description |
|------|-------------|
| `--gcp-project-id` | GCP Cloud SQL project identifier |
| `--gcp-instance-id` | GCP Cloud SQL instance identifier |

#### Active Directory Flags

| Flag | Description |
|------|-------------|
| `--ad-domain` | Active Directory domain |
| `--ad-spn` | Service Principal Name |
| `--ad-keytab-file` | Kerberos keytab file |

#### Examples

```bash
# Generate config for a self-hosted PostgreSQL
teleport db configure create \
  --proxy=proxy.example.com:443 \
  --token=db-token \
  --name=my-postgres --protocol=postgres --uri=postgres.internal:5432 \
  -o file:///etc/teleport.yaml

# Generate config with RDS auto-discovery
teleport db configure create \
  --proxy=proxy.example.com:443 \
  --token=db-token \
  --rds-discovery=us-east-1 --rds-discovery=us-west-2 \
  --aws-tags=env=prod \
  -o file:///etc/teleport.yaml

# Generate config with Azure database discovery
teleport db configure create \
  --proxy=proxy.example.com:443 \
  --token=db-token \
  --azure-postgres-discovery=eastus \
  --azure-subscription=12345678-1234-1234-1234-123456789012 \
  -o file:///etc/teleport.yaml
```

### teleport db configure bootstrap

Bootstrap the necessary IAM configuration for the database agent.

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--config` | `-c` | Path to a configuration file | `/etc/teleport.yaml` |
| `--manual` | | Print instructions instead of applying directly | `false` |
| `--policy-name` | | Name of the Teleport Database agent policy | `DatabaseAccess` |
| `--confirm` | | Apply changes without confirmation prompt | `false` |
| `--attach-to-role` | | Role name to attach policy to (mutually exclusive with --attach-to-user) | |
| `--attach-to-user` | | User name to attach policy to (mutually exclusive with --attach-to-role) | |
| `--assumes-roles` | | Additional IAM roles to assume (comma-separated) | |

```bash
# Bootstrap with manual review
teleport db configure bootstrap --manual

# Bootstrap and attach to an IAM role
teleport db configure bootstrap \
  --attach-to-role=TeleportDatabaseAgent \
  --confirm

# Bootstrap with custom policy name
teleport db configure bootstrap \
  --policy-name=CustomDatabaseAccess \
  --attach-to-role=MyRole \
  --confirm
```

### teleport db configure aws print-iam

Generate and display IAM policies.

| Flag | Short | Description |
|------|-------|-------------|
| `--types` | `-r` | Database types: rds, rdsproxy, redshift, redshift-serverless, elasticache, elasticache-serverless, memorydb, keyspace, dynamodb, opensearch, docdb |
| `--role` | | IAM role name (mutually exclusive with --user) |
| `--user` | | IAM user name (mutually exclusive with --role) |
| `--policy` | | Only print IAM policy document |
| `--policy-name` | | Name of the policy (default: `DatabaseAccess`) |
| `--assumes-roles` | | Additional IAM roles to assume |

```bash
# Print IAM policy for RDS access
teleport db configure aws print-iam --types=rds --role=TeleportDatabaseAgent

# Print policy for multiple database types
teleport db configure aws print-iam --types=rds,redshift,dynamodb --role=TeleportDatabaseAgent

# Print only the policy document
teleport db configure aws print-iam --types=rds --policy
```

### teleport db configure aws create-iam

Generate, create, and attach IAM policies.

| Flag | Short | Description |
|------|-------|-------------|
| `--types` | `-r` | Database types (same as print-iam) |
| `--name` | | Created policy name (default: `DatabaseAccess`) |
| `--confirm` | | Apply changes without confirmation |
| `--role` | | IAM role name (mutually exclusive with --user) |
| `--user` | | IAM user name (mutually exclusive with --role) |
| `--assumes-roles` | | Additional IAM roles to assume |

```bash
# Create and attach IAM policy for RDS
teleport db configure aws create-iam \
  --types=rds --role=TeleportDatabaseAgent --confirm

# Create policy for multiple database types
teleport db configure aws create-iam \
  --types=rds,elasticache,memorydb \
  --role=TeleportDatabaseAgent --confirm
```

---

## teleport join openssh

Join an existing OpenSSH server to a Teleport cluster without replacing sshd.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--proxy-server` | | Address of the proxy server | |
| `--token` | | Invitation token or path to file | |
| `--join-method` | | Method to use: token, iam, ec2 | |
| `--openssh-config` | | Path to the OpenSSH config file | `/etc/ssh/sshd_config` |
| `--data-dir` | | Path to directory to store teleport data | `/var/lib/teleport` |
| `--restart-sshd` | | Restart OpenSSH after configuration | `true` |
| `--sshd-check-command` | | Command to check OpenSSH config validity | `sshd -t -f` |
| `--sshd-restart-command` | | Command to restart OpenSSH | |
| `--labels` | | Comma-separated list of labels | |
| `--address` | | Hostname or IP address of this OpenSSH node | |
| `--additional-principals` | | Additional principal to include (repeatable) | |
| `--insecure` | | Disable certificate validation | `false` |
| `--skip-version-check` | | Skip version checking | `false` |
| `--debug` | `-d` | Enable verbose logging to stderr | `false` |

### Examples

```bash
# Join with token method
teleport join openssh \
  --proxy-server=proxy.example.com:443 \
  --token=openssh-token \
  --join-method=token \
  --labels=env=prod,os=ubuntu

# Join with IAM method (AWS)
teleport join openssh \
  --proxy-server=proxy.example.com:443 \
  --join-method=iam \
  --labels=env=prod,region=us-east-1

# Join with custom address and principals
teleport join openssh \
  --proxy-server=proxy.example.com:443 \
  --token=openssh-token \
  --join-method=token \
  --address=10.0.1.50 \
  --additional-principals=web01.internal

# Join without restarting sshd (manual restart)
teleport join openssh \
  --proxy-server=proxy.example.com:443 \
  --token=openssh-token \
  --join-method=token \
  --no-restart-sshd

# Join with custom sshd restart command
teleport join openssh \
  --proxy-server=proxy.example.com:443 \
  --token=openssh-token \
  --join-method=token \
  --sshd-restart-command="systemctl restart sshd"
```

---

## teleport discovery bootstrap

Bootstrap the necessary configuration for the discovery agent.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--config` | `-c` | Path to a configuration file | `/etc/teleport.yaml` |
| `--confirm` | | Apply changes without confirmation | `false` |
| `--manual` | | Print instructions instead of applying | `false` |
| `--proxy` | | Teleport proxy address | |
| `--policy-name` | | Name of the Discovery service policy | `TeleportEC2Discovery` |
| `--attach-to-role` | | Role name to attach policy to | |
| `--attach-to-user` | | User name to attach policy to | |
| `--assume-role-arn` | | Optional AWS IAM role to assume while bootstrapping | |
| `--assumes-roles` | | Additional IAM roles to assume | |
| `--external-id` | | Optional AWS external ID for assuming roles | |
| `--database-service-role` | | Role name to attach database access policies to | |
| `--database-service-policy-name` | | Policy name for database service bootstrap | `DatabaseAccess` |

### Examples

```bash
# Bootstrap discovery agent
teleport discovery bootstrap \
  --attach-to-role=TeleportDiscovery --confirm

# Bootstrap with manual review
teleport discovery bootstrap --manual

# Bootstrap with database service integration
teleport discovery bootstrap \
  --attach-to-role=TeleportDiscovery \
  --database-service-role=TeleportDatabaseAgent \
  --confirm

# Bootstrap assuming an IAM role
teleport discovery bootstrap \
  --attach-to-role=TeleportDiscovery \
  --assume-role-arn=arn:aws:iam::123456789012:role/bootstrap-role \
  --confirm
```

---

## teleport integration configure

Configure cloud integrations (AWS, Azure, GCP). All subcommands support `--confirm` to apply without confirmation.

### Subcommand Summary

| Subcommand | Description |
|------------|-------------|
| `deployservice-iam` | Create IAM Roles for AWS OIDC Deploy Service |
| `ec2-ssm-iam` | Add IAM permissions and SSM Document for EC2 Auto Discover |
| `aws-app-access-iam` | Add IAM permissions for AWS App Access |
| `eks-iam` | Add IAM permissions for EKS cluster enrollment |
| `session-summaries bedrock` | Add IAM permissions for Session Summaries using AWS Bedrock |
| `access-graph aws-iam` | Add AWS IAM permissions for Access Graph sync |
| `access-graph azure` | Add Azure permissions for Access Graph sync |
| `awsoidc-idp` | Create IAM IdP (OIDC) in AWS account |
| `listdatabases-iam` | Add IAM permissions to list RDS databases |
| `externalauditstorage` | Bootstrap infrastructure and IAM for External Audit Storage |
| `azure-oidc` | Configure Azure / Entra ID OIDC integration |
| `samlidp gcp-workforce` | Configure GCP Workforce Identity Federation pool and SAML provider |
| `awsra-trust-anchor` | Configure AWS IAM Roles Anywhere Integration |

### deployservice-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--cluster` | Yes | Teleport cluster name |
| `--name` | Yes | Integration name |
| `--aws-region` | Yes | AWS region |
| `--role` | Yes | IAM role name |
| `--task-role` | Yes | IAM task role name |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### ec2-ssm-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--role` | Yes | IAM role name |
| `--aws-region` | Yes | AWS region |
| `--cluster` | Yes | Teleport cluster name |
| `--name` | Yes | Integration name |
| `--ssm-document-name` | No | SSM document name |
| `--proxy-public-url` | No | Proxy public URL |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### aws-app-access-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--role` | Yes | IAM role name |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### eks-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--aws-region` | Yes | AWS region |
| `--role` | Yes | IAM role name |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### session-summaries bedrock

| Flag | Required | Description |
|------|----------|-------------|
| `--role` | Yes | IAM role name |
| `--resource` | No | Bedrock resource (default: `*`) |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### access-graph aws-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--role` | Yes | IAM role name |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |
| `--sqs-queue-url` | No | SQS queue URL |
| `--cloud-trail-bucket` | No | CloudTrail S3 bucket |
| `--kms-key` | No | KMS key (repeatable) |
| `--eks-audit-logs` | No | Enable EKS audit logs |

### access-graph azure

| Flag | Required | Description |
|------|----------|-------------|
| `--managed-identity` | Yes | Azure managed identity name |
| `--role-name` | Yes | Azure role name |
| `--subscription-id` | No | Azure subscription ID |
| `--confirm` | No | Apply without confirmation |

### awsoidc-idp

| Flag | Required | Description |
|------|----------|-------------|
| `--cluster` | Yes | Teleport cluster name |
| `--name` | Yes | Integration name |
| `--role` | Yes | IAM role name |
| `--proxy-public-url` | Yes | Proxy public URL |
| `--policy-preset` | No | Policy preset |
| `--confirm` | No | Apply without confirmation |
| `--insecure` | No | Disable cert validation |

### listdatabases-iam

| Flag | Required | Description |
|------|----------|-------------|
| `--aws-region` | Yes | AWS region |
| `--role` | Yes | IAM role name |
| `--aws-account-id` | No | AWS account ID |
| `--confirm` | No | Apply without confirmation |

### externalauditstorage

| Flag | Required | Description |
|------|----------|-------------|
| `--aws-region` | Yes | AWS region |
| `--cluster-name` | Yes | Teleport cluster name |
| `--integration` | Yes | Integration name |
| `--role` | Yes | IAM role name |
| `--policy` | Yes | IAM policy name |
| `--session-recordings` | Yes | S3 bucket for session recordings |
| `--audit-events` | Yes | S3 bucket for audit events |
| `--athena-results` | Yes | S3 bucket for Athena results |
| `--athena-workgroup` | Yes | Athena workgroup name |
| `--glue-database` | Yes | Glue database name |
| `--glue-table` | Yes | Glue table name |
| `--bootstrap` | No | Run bootstrap (default: false) |
| `--aws-partition` | No | AWS partition (default: `aws`) |
| `--aws-account-id` | No | AWS account ID |

### azure-oidc

| Flag | Required | Description |
|------|----------|-------------|
| `--proxy-public-addr` | Yes | Proxy public address |
| `--auth-connector-name` | Yes | Auth connector name |
| `--access-graph` | No | Enable Access Graph |
| `--skip-oidc-integration` | No | Skip OIDC integration |

### samlidp gcp-workforce

| Flag | Required | Description |
|------|----------|-------------|
| `--org-id` | Yes | GCP organization ID |
| `--pool-name` | Yes | Workforce Identity pool name |
| `--pool-provider-name` | Yes | Workforce Identity pool provider name |
| `--idp-metadata-url` | Yes | IdP metadata URL |

### awsra-trust-anchor

| Flag | Required | Description |
|------|----------|-------------|
| `--cluster` | Yes | Teleport cluster name |
| `--name` | Yes | Integration name |
| `--trust-anchor` | Yes | Trust anchor name |
| `--trust-anchor-cert-b64` | Yes | Base64-encoded trust anchor certificate |
| `--sync-profile` | Yes | Sync profile name |
| `--sync-role` | Yes | Sync role name |
| `--confirm` | No | Apply without confirmation |

---

## teleport backend

Commands for managing cluster state backend data. All subcommands accept `-c, --config` (default: `/etc/teleport.yaml`).

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `get <key>` | Retrieve a single item |
| `ls [prefix]` | List keys (optional prefix filter) |
| `edit <key>` | Modify a single item (opens editor) |
| `rm <key>` | Remove a single item |
| `clone` | Clone data from source to destination backend |

### get / ls Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--format` | `-f` | Output format: text, json, yaml | `text` |

### clone

Clones data from a source to a destination backend. Requires a clone configuration YAML file.

```yaml
# clone-config.yaml
src:
  type: sqlite
  path: /var/lib/teleport_data
dst:
  type: dynamodb
  region: us-east-1
  table: teleport_backend
parallel: 100
force: false
```

```bash
# Clone backend data
teleport backend clone clone-config.yaml

# Get a backend key
teleport backend get /tokens/my-token

# List all keys under a prefix
teleport backend ls /tokens/
teleport backend ls /tokens/ -f json

# Edit a backend item
teleport backend edit /tokens/my-token

# Remove a backend item
teleport backend rm /tokens/my-token
```

---

## teleport debug

Debug commands for operational troubleshooting. All subcommands accept `-c, --config` (default: `/etc/teleport.yaml`).

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `set-log-level <LEVEL>` | Change the log level at runtime |
| `get-log-level` | Fetch the current log level |
| `profile [PROFILES]` | Export application profiles in pprof format |
| `readyz` | Check if the instance is ready to serve requests |
| `metrics` | Fetch the cluster's Prometheus metrics |

### Log Levels

Case-insensitive: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`

### Profile

Export pprof profiles as a `.tar.gz` to stdout.

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--seconds` | `-s` | Profile duration (0 = snapshot) | `0` |

Supported profiles: `cmdline`, `goroutine`, `mutex`, `threadcreate`, `trace`, `allocs`, `block`, `heap`, `profile`

Default profiles (when none specified): `goroutine`, `heap`, `profile`

### Examples

```bash
# Change log level at runtime
teleport debug set-log-level DEBUG

# Check current log level
teleport debug get-log-level

# Check instance readiness
teleport debug readyz

# Fetch Prometheus metrics
teleport debug metrics

# Export default profiles (snapshot)
teleport debug profile > profiles.tar.gz

# Export specific profiles with duration
teleport debug profile --seconds=30 goroutine,heap,profile > profiles.tar.gz

# Export all profiles
teleport debug profile cmdline,goroutine,mutex,threadcreate,trace,allocs,block,heap,profile > profiles.tar.gz
```

---

## teleport install systemd

Creates a systemd unit file configuration.

### Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--env-file` | | Full path to the environment file | `/etc/default/teleport` |
| `--pid-file` | | Full path to the PID file | `/run/teleport.pid` |
| `--fd-limit` | | Maximum number of open file descriptors | `524288` |
| `--teleport-path` | | Full path to the Teleport binary | |
| `--output` | `-o` | Output destination | `stdout` |

### Examples

```bash
# Generate systemd unit file to stdout
teleport install systemd

# Write unit file directly
teleport install systemd -o file:///etc/systemd/system/teleport.service

# Generate with custom paths
teleport install systemd \
  --teleport-path=/usr/local/bin/teleport \
  --env-file=/etc/sysconfig/teleport \
  --pid-file=/var/run/teleport.pid \
  -o file:///etc/systemd/system/teleport.service

# Then enable and start
# systemctl daemon-reload
# systemctl enable teleport
# systemctl start teleport
```

---

## teleport tpm identify

Output identifying information related to the TPM detected on the system. Used when setting up tbot with the `tpm` join method.

```bash
teleport tpm identify
```

No additional flags.

---

## Service Roles

When running `teleport start --roles=`, the following roles are available:

| Role | Description |
|------|-------------|
| **auth** | Authentication and authorization service. Acts as the cluster CA. Issues and validates certificates. Manages users, roles, tokens, and cluster state. Only one auth service cluster is active (HA with multiple instances using shared backend). |
| **proxy** | Client entry point. Handles TLS termination, web UI, SSH proxy, reverse tunnels, and protocol routing. Clients connect to the proxy, which routes to the appropriate backend service. Supports HTTPS, SSH, database, Kubernetes, and application protocols on a single port. |
| **node** | SSH node service. Registers with the auth service and accepts SSH connections routed through the proxy. Provides session recording, RBAC enforcement, and audit logging. |
| **app** | Application proxy service. Exposes internal web applications, TCP applications, and cloud provider APIs (AWS, Azure, GCP) through Teleport with identity-aware access. |
| **db** | Database proxy service. Provides authenticated access to databases (PostgreSQL, MySQL, MongoDB, etc.) with per-query audit logging and short-lived credentials. |

Additional roles managed via configuration file (not `--roles` flag):

- **kube** -- Kubernetes access service. Provides authenticated kubectl access with impersonation, RBAC, and session recording.
- **discovery** -- Dynamic cloud resource discovery. Automatically finds and registers AWS, Azure, and GCP resources (EC2 instances, RDS databases, EKS clusters, etc.).

### Multi-Role Deployments

A single Teleport instance can run multiple roles simultaneously:

```bash
# All-in-one deployment (development/small clusters)
teleport start --roles=proxy,auth,node,app,db

# Dedicated auth server
teleport start --roles=auth

# Proxy-only instance (load-balanced)
teleport start --roles=proxy --auth-server=auth.internal:3025

# Node agent
teleport start --roles=node --auth-server=auth.internal:3025 --token=node-token

# App + DB agent
teleport start --roles=app,db --auth-server=auth.internal:3025 --token=agent-token
```

---

## Configuration File Reference

### Minimal Configuration

```yaml
version: v3
teleport:
  nodename: my-node
  data_dir: /var/lib/teleport
  auth_token: invite-token
  auth_server: auth.example.com:3025

auth_service:
  enabled: true
  cluster_name: example.com

proxy_service:
  enabled: true
  web_listen_addr: 0.0.0.0:3080
  public_addr: proxy.example.com:443

ssh_service:
  enabled: true
  labels:
    env: prod
```

### Full Structure Overview

```yaml
version: v3

teleport:
  nodename: hostname           # node name (default: OS hostname)
  data_dir: /var/lib/teleport  # data directory
  auth_token: token-value      # join token or path to file
  ca_pin:                      # CA pins for auth server validation
    - "sha256:..."
  auth_server: auth:3025       # auth server address
  advertise_ip: 10.0.0.1       # IP to advertise if behind NAT
  log:
    output: stderr             # stderr, stdout, syslog, or file path
    severity: INFO             # TRACE, DEBUG, INFO, WARN, ERROR
    format:
      output: text             # text or json

auth_service:
  enabled: true
  cluster_name: example.com
  listen_addr: 0.0.0.0:3025
  tokens:                      # static tokens for joining
    - "node:invite-token"
    - "proxy:proxy-token"

proxy_service:
  enabled: true
  web_listen_addr: 0.0.0.0:3080
  listen_addr: 0.0.0.0:3023
  tunnel_listen_addr: 0.0.0.0:3024
  public_addr: proxy.example.com:443
  https_keypairs:
    - key_file: /etc/letsencrypt/live/example.com/privkey.pem
      cert_file: /etc/letsencrypt/live/example.com/fullchain.pem
  acme:
    enabled: true
    email: admin@example.com
  kube_listen_addr: 0.0.0.0:3026
  mysql_listen_addr: 0.0.0.0:3036

ssh_service:
  enabled: true
  listen_addr: 0.0.0.0:3022
  labels:
    env: prod
    team: backend
  commands:                    # dynamic labels
    - name: hostname
      command: [hostname]
      period: 1m

app_service:
  enabled: true
  apps:
    - name: grafana
      uri: http://localhost:3000
      labels:
        env: prod
    - name: aws-console
      cloud: AWS

db_service:
  enabled: true
  databases:
    - name: my-postgres
      protocol: postgres
      uri: postgres.internal:5432
      labels:
        env: prod
    - name: my-mysql
      protocol: mysql
      uri: mysql.internal:3306

kubernetes_service:
  enabled: true
  listen_addr: 0.0.0.0:3027

discovery_service:
  enabled: true
  aws:
    - types: ["rds"]
      regions: ["us-east-1", "us-west-2"]
      tags:
        env: ["prod"]
    - types: ["ec2"]
      regions: ["us-east-1"]
      install:
        join_params:
          token_name: ec2-token
          method: iam
```

### Config File Locations

- Default: `/etc/teleport.yaml`
- Override with `-c` or `--config` flag
- Generate with `teleport configure` or `teleport node configure`
- Validate with `teleport configure --test=/path/to/config.yaml`

---

## Join Methods

All join methods supported across `teleport configure`, `teleport node configure`, and `teleport join openssh`:

| Method | Description | Secret-Free |
|--------|-------------|:-----------:|
| `token` | Static or dynamic invitation token | No |
| `iam` | AWS IAM role identity | Yes |
| `ec2` | AWS EC2 instance identity document | Yes |
| `gcp` | GCP VM service account identity | Yes |
| `azure` | Azure VM managed identity | Yes |
| `kubernetes` | Kubernetes service account token | Yes |
| `github` | GitHub Actions OIDC token | Yes |
| `gitlab` | GitLab CI OIDC token | Yes |
| `circleci` | CircleCI OIDC token | Yes |
| `spacelift` | Spacelift run identity | Yes |
| `terraform_cloud` | Terraform Cloud run identity | Yes |
| `azure_devops` | Azure DevOps pipeline identity | Yes |
| `bitbucket` | Bitbucket Pipelines OIDC token | Yes |
| `oracle` | Oracle Cloud Infrastructure identity | Yes |
| `env0` | env0 environment run identity | Yes |
| `tpm` | Hardware TPM attestation | Yes |
| `bound_keypair` | Pre-registered keypair | Yes |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TELEPORT_CONFIG` | Path to configuration file (alternative to `--config`) |
| `TELEPORT_DEBUG` | Enable debug logging (`1` or `true`) |
| `TELEPORT_AUTH_SERVER` | Auth server address |
| `TELEPORT_PROXY` | Proxy server address |
| `TELEPORT_DATA_DIR` | Data directory path |
| `TELEPORT_NODE_NAME` | Node name |

---

## Diagnostic Endpoint

When started with `--diag-addr`, Teleport exposes health and metrics endpoints:

| Endpoint | Description |
|----------|-------------|
| `/healthz` | Health check |
| `/readyz` | Readiness check (available via `teleport debug readyz`) |
| `/livez` | Liveness check |
| `/metrics` | Prometheus metrics (available via `teleport debug metrics`) |

```bash
# Start with diagnostic endpoint
teleport start --diag-addr=0.0.0.0:3434

# Check health
curl http://localhost:3434/healthz

# Check readiness
curl http://localhost:3434/readyz
teleport debug readyz

# Scrape metrics
curl http://localhost:3434/metrics
teleport debug metrics
```

Use with Kubernetes probes:

```yaml
livenessProbe:
  httpGet:
    path: /livez
    port: 3434
readinessProbe:
  httpGet:
    path: /readyz
    port: 3434
```

---

## Troubleshooting

### Enable Debug Logging

```bash
# Via flag
teleport start --debug

# Via environment variable
TELEPORT_DEBUG=1 teleport start

# Change at runtime (without restart)
teleport debug set-log-level DEBUG

# Reset to default
teleport debug set-log-level INFO
```

### Common Issues

**"token not found" or "access denied" on join:**

- Verify the token exists: `tctl tokens ls`
- Check token has the correct role (`Node`, `Proxy`, `App`, `Db`, etc.)
- For IAM join: verify the IAM role ARN matches the token's allow rules
- For EC2 join: verify the instance identity document matches
- Ensure the auth server is reachable from the joining node

**Service fails to start with "bind: address already in use":**

- Check for existing Teleport processes: `ps aux | grep teleport`
- Verify port availability: default ports are 3022 (SSH), 3023 (proxy SSH), 3024 (reverse tunnel), 3025 (auth), 3080 (web)
- Use `--listen-ip` to bind to a specific interface

**"certificate has expired" or TLS errors:**

- Check system clock synchronization (NTP)
- For self-signed certs: use `--insecure` only for testing
- Verify `--ca-pin` matches the auth server CA
- Check proxy certificate validity and chain

**Auth service not reachable:**

- Verify `--auth-server` points to the correct address
- Check firewall rules allow port 3025 (auth)
- For proxy-based connections, ensure reverse tunnel is established

**Config file errors:**

- Validate the config: `teleport configure --test=/etc/teleport.yaml`
- Ensure config version is `v3` (latest)
- Check YAML indentation and syntax

**Database proxy not working:**

- Verify `--protocol` matches the actual database type
- Check `--uri` is reachable from the Teleport agent
- For AWS databases: verify IAM policies are configured (`teleport db configure bootstrap`)
- For Cloud SQL: verify GCP service account permissions

**Discovery agent not finding resources:**

- Verify IAM permissions: `teleport discovery bootstrap --manual`
- Check resource tags match the discovery configuration
- Ensure the discovery region is correct
- Review logs with `--debug` for API errors

**OpenSSH join failing:**

- Verify sshd config is valid: `sshd -t -f /etc/ssh/sshd_config`
- Check the proxy server is reachable
- Verify the join method and token are correct
- Check `--openssh-config` points to the right file

**Backend operations failing:**

- Ensure you are running on the auth server (or have access to the backend)
- Check backend configuration in `/etc/teleport.yaml`
- Use `teleport backend ls` to verify backend connectivity

### Performance Profiling

```bash
# Export goroutine and heap profiles
teleport debug profile goroutine,heap > profiles.tar.gz

# CPU profile for 30 seconds
teleport debug profile --seconds=30 profile > cpu-profile.tar.gz

# All profiles
teleport debug profile cmdline,goroutine,mutex,threadcreate,trace,allocs,block,heap,profile > all-profiles.tar.gz
```

---

## Key Defaults

| Setting | Default |
|---------|---------|
| Config file | `/etc/teleport.yaml` |
| Listen IP | `0.0.0.0` |
| Auth server | `127.0.0.1:3025` |
| Data directory | `/var/lib/teleport` |
| Config version | `v3` |
| OpenSSH config | `/etc/ssh/sshd_config` |
| Kerberos config | `/etc/krb5.conf` |
| Systemd env file | `/etc/default/teleport` |
| Systemd PID file | `/run/teleport.pid` |
| FD limit | `524288` |
| Database policy name | `DatabaseAccess` |
| Discovery policy name | `TeleportEC2Discovery` |
| AWS partition | `aws` |
| Default roles (start) | `node,proxy,auth` |
| Default SSH port | `3022` |
| Default auth port | `3025` |
| Default proxy web port | `3080` |
| Default proxy SSH port | `3023` |
| Default reverse tunnel port | `3024` |
