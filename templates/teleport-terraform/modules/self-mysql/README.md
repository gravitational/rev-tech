# MySQL Instance Module

Creates a self-hosted MySQL database with TLS encryption and certificate-based authentication for Teleport database access demonstrations.

## Overview

- **Use Case:** Self-hosted database access with certificate authentication
- **Teleport Features:** Database access, mutual TLS, certificate-based auth, session recording
- **Infrastructure:** EC2 instance with MariaDB, custom CA, and Teleport agent

## Usage

```

## Troubleshooting

### Multiple Services Status
This instance runs both database and SSH services. Check both when troubleshooting:

```bash
# SSH into the server first
tsh ssh ec2-user@dev-mysql

# Check all Teleport services
sudo systemctl status teleport
sudo journalctl -u teleport -f

# Check MySQL service
sudo systemctl status mariadb
sudo tail -f /var/log/mysqld.log
```

### Common Issues
- **Database Connection Failed:** Check TLS certificates and MySQL status
- **SSH Access Denied:** Verify user roles and node labels
- **Certificate Errors:** Ensure Teleport DB CA is properly configured
- **Agent Registration Failed:** Check provision token validity

### Service-Specific Debugging
```bash
# Database service issues
tsh db ls --debug
tctl db ls

# SSH service issues  
tsh ls --debug
tctl nodes ls

# View complete Teleport configuration
sudo cat /etc/teleport.yaml
```hcl
module "mysql_instance" {
  source = "../../modules/mysql_instance"
  
  env              = "dev"
  user             = "engineer@company.com"
  proxy_address    = "teleport.company.com"
  teleport_version = "17.5.2"
  teleport_db_ca   = data.http.teleport_db_ca_cert.response_body
  
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## What It Creates

### AWS Resources
- **EC2 Instance:** Amazon Linux 2023 with MariaDB 10.5
- **TLS Certificates:** Custom CA and server certificates for MySQL

### Teleport Resources
- **Provision Token:** For database and SSH service registration
- **Database Users:** `writer` and `reader` with certificate authentication

### Teleport Services Enabled
- ** Database Service:** MySQL database access with certificate auth
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
  compliance  = "pci"            # Add compliance requirements
}
```

## Demo Commands

### Database Access
```bash
# List databases
tsh db ls --labels=tier=dev

# Connect as reader
tsh db connect mysql-dev --db-user=reader

# Connect as writer
tsh db connect mysql-dev --db-user=writer

# Show databases
SHOW DATABASES;

# Test permissions (reader vs writer)
CREATE TABLE test_table (id INT);  # Will fail for reader
```

### SSH Access (Server Management)
```bash
# List SSH nodes
tsh ls --labels=tier=dev

# SSH into the database server
tsh ssh ec2-user@dev-mysql

# Check MySQL status
sudo systemctl status mariadb

# View MySQL logs
sudo tail -f /var/log/mysqld.log
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment name | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `teleport_db_ca` | Teleport DB CA certificate | `string` | - |
| `mysql_hostname` | Hostname for TLS certificate | `string` | `"mysql.example.internal"` |
| `ami_id` | AMI ID for instance | `string` | - |
| `instance_type` | EC2 instance type | `string` | - |
| `subnet_id` | Subnet for instance | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label | `string` | `"engineering"` |

## Outputs

| Output | Description |
|--------|-------------|
| `ca_cert` | Custom CA certificate used for MySQL TLS |

## Security Features

- **Mutual TLS:** All database connections use client certificates
- **Certificate Authentication:** Users authenticate via X.509 certificates
- **Secure Transport:** MySQL configured to require TLS connections
- **Custom CA:** Self-signed CA for demonstration purposes

## Database Users

| User | Permissions | Use Case |
|------|-------------|----------|
| `writer` | Full privileges on all databases | Administrative tasks, data modification |
| `reader` | SELECT and SHOW VIEW only | Read-only access, reporting queries |

## Integration

This module is designed to work with the `registration` module:

```hcl
module "mysql_registration" {
  source        = "../../modules/registration"
  resource_type = "database"
  name          = "mysql-${var.env}"
  protocol      = "mysql"
  uri           = "localhost:3306"
  ca_cert_chain = module.mysql_instance.ca_cert
  labels = {
    tier = var.env
    team = var.team
  }
}
```