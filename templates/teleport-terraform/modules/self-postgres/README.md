# PostgreSQL Instance Module

Creates a self-hosted PostgreSQL database with TLS encryption and certificate-based authentication for Teleport database access demonstrations.

## Overview

- **Use Case:** Self-hosted database access with certificate authentication
- **Teleport Features:** Database access, mutual TLS, certificate-based auth, session recording
- **Infrastructure:** EC2 instance with PostgreSQL 15, custom CA, and Teleport agent

## Usage

```hcl
module "postgres_instance" {
  source = "../../modules/postgres_instance"
  
  env               = "dev"
  user              = "engineer@company.com"
  proxy_address     = "teleport.company.com"
  teleport_version  = "17.5.2"
  teleport_db_ca    = data.http.teleport_db_ca_cert.response_body
  postgres_hostname = "postgres.dev.internal"
  
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## What It Creates

### AWS Resources
- **EC2 Instance:** Amazon Linux 2023 with PostgreSQL 15
- **TLS Certificates:** Custom CA and server certificates for PostgreSQL

### Teleport Resources
- **Provision Token:** For database and SSH service registration
- **Database Users:** `writer` and `reader` with certificate authentication

### Teleport Services Enabled
- ** Database Service:** PostgreSQL database access with certificate auth
- ** SSH Service:** Server management and troubleshooting access

## Label Structure & Access Control

This module applies consistent labels for RBAC and dynamic discovery:

```yaml
Labels Applied:
  tier: "dev"          # From var.env - environment-based access
  team: "engineering"  # From var.team - team-based access
```

### RBAC Integration
```yaml
# Example Teleport role using these labels:
allow:
  db_labels:
    tier: ["dev", "staging"]     # Access dev and staging DBs
    team: ["engineering"]        # Only engineering team
  node_labels:
    tier: ["dev"]                # SSH access to dev servers
    team: ["engineering"]        # Same team restriction
```

### Customization
To adapt for your environment, modify the labels in your configuration:
```hcl
# Custom labels for your organization
labels = {
  tier        = "production"     # or "dev", "staging", "qa"
  team        = "platform"       # or "frontend", "backend", "data"
  environment = "us-west-2"      # Add region-specific access
  compliance  = "hipaa"          # Add compliance requirements
}
```

## Demo Commands

### Database Access
```bash
# List databases
tsh db ls --labels=tier=dev

# Connect as reader
tsh db connect postgres-dev --db-user=reader

# Connect as writer
tsh db connect postgres-dev --db-user=writer

# Show databases
\l

# Test permissions (reader vs writer)
CREATE TABLE test_table (id SERIAL);  # Will fail for reader
SELECT * FROM pg_tables;              # Works for both
```

### SSH Access (Server Management)
```bash
# List SSH nodes
tsh ls --labels=tier=dev

# SSH into the database server
tsh ssh ec2-user@dev-postgres

# Check PostgreSQL status
sudo systemctl status postgresql

# View PostgreSQL logs
sudo tail -f /var/lib/pgsql/data/log/postgresql-*.log

# Check database connections
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment name | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `teleport_db_ca` | Teleport DB CA certificate | `string` | - |
| `postgres_hostname` | Hostname for TLS certificate | `string` | `"postgres.example.internal"` |
| `ami_id` | AMI ID for instance | `string` | - |
| `instance_type` | EC2 instance type | `string` | - |
| `subnet_id` | Subnet for instance | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label | `string` | `"engineering"` |

## Outputs

| Output | Description |
|--------|-------------|
| `ca_cert` | Custom CA certificate used for PostgreSQL TLS |

## Security Features

- **Mutual TLS:** All database connections use client certificates
- **Certificate Authentication:** Users authenticate via X.509 certificates
- **SSL Required:** PostgreSQL configured to require SSL connections
- **Custom CA:** Self-signed CA for demonstration purposes
- **pg_hba.conf:** Configured for cert-based authentication priority

## Database Users

| User | Permissions | Use Case |
|------|-------------|----------|
| `writer` | Full privileges on postgres database | Administrative tasks, data modification |
| `reader` | CONNECT privilege only | Read-only access, requires additional grants |

## PostgreSQL Configuration

### SSL Configuration
```sql
-- Key PostgreSQL settings applied:
ssl = on
ssl_cert_file = 'certs/server.crt'
ssl_key_file = 'certs/server.key'
ssl_ca_file = 'certs/server.cas'
```

### Authentication Priority (pg_hba.conf)
```
# Certificate auth takes priority
hostssl all all ::/0      cert
hostssl all all 0.0.0.0/0 cert

# Fallback local auth
local   all all           peer
host    all all 127.0.0.1/32 ident
host    all all ::1/128      ident
```

## Integration

This module is designed to work with the `registration` module:

```hcl
module "postgres_registration" {
  source        = "../../modules/registration"
  resource_type = "database"
  name          = "postgres-${var.env}"
  protocol      = "postgres"
  uri           = "localhost:5432"
  ca_cert_chain = module.postgres_instance.ca_cert
  labels = {
    tier = var.env
    team = var.team
  }
}
```

## Troubleshooting

### Multiple Services Status
This instance runs both database and SSH services. Check both when troubleshooting:

```bash
# SSH into the server first
tsh ssh ec2-user@dev-postgres

# Check all Teleport services
sudo systemctl status teleport
sudo journalctl -u teleport -f

# Check PostgreSQL service
sudo systemctl status postgresql
sudo tail -f /var/lib/pgsql/data/log/postgresql-*.log

# Test database connectivity
sudo -u postgres psql -c "SELECT version();"
```

### Common Issues
- **Database Connection Failed:** Check TLS certificates and PostgreSQL status
- **SSH Access Denied:** Verify user roles and node labels
- **Certificate Errors:** Ensure Teleport DB CA is properly configured
- **SSL Connection Required:** All connections must use SSL
- **Authentication Failed:** Check certificate-based auth configuration

### Service-Specific Debugging
```bash
# Database service issues
tsh db ls --debug
tctl db ls
sudo -u postgres psql -c "SELECT * FROM pg_stat_ssl;"

# SSH service issues  
tsh ls --debug
tctl nodes ls

# PostgreSQL SSL debugging
sudo -u postgres psql -c "SHOW ssl;"
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity WHERE ssl IS TRUE;"

# Certificate verification
openssl verify -CAfile /var/lib/pgsql/data/certs/server.cas /var/lib/pgsql/data/certs/server.crt
```

### User Permission Troubleshooting
```sql
-- Connect as writer to check/grant permissions
\c postgres
\du  -- List users and roles

-- Grant additional permissions to reader if needed
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reader;
GRANT USAGE ON SCHEMA public TO reader;
```

## Features

- **PostgreSQL 15:** Latest stable version with modern features
- **X.509 Authentication:** Certificate-based user authentication
- **TLS Encryption:** All connections encrypted with custom CA
- **Enhanced Recording:** Database session recording via Teleport
- **Dual Service Access:** Both database and SSH access for complete management
- **Configurable Hostname:** Custom hostname for TLS certificate

## Performance Considerations

- **Connection Pooling:** Consider implementing connection pooling for production use
- **SSL Overhead:** TLS adds ~10% performance overhead
- **Certificate Rotation:** Plan for certificate renewal in production
- **Monitoring:** Use PostgreSQL built-in monitoring for performance tuning