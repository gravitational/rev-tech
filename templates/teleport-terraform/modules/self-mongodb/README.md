# MongoDB Instance Module

Creates a self-hosted MongoDB database with TLS encryption and certificate-based authentication for Teleport database access demonstrations.

## Overview

- **Use Case:** Self-hosted NoSQL database access with certificate authentication
- **Teleport Features:** Database access, mutual TLS, certificate-based auth, session recording
- **Infrastructure:** EC2 instance with MongoDB Community 7.0, custom CA, and Teleport agent

## Usage

```hcl
module "mongodb_instance" {
  source = "../../modules/mongodb_instance"
  
  env               = "dev"
  user              = "engineer@company.com"
  proxy_address     = "teleport.company.com"
  teleport_version  = "17.5.2"
  teleport_db_ca    = data.http.teleport_db_ca_cert.response_body
  mongodb_hostname  = "mongodb.dev.internal"
  
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.small"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## What It Creates

### AWS Resources
- **EC2 Instance:** Amazon Linux 2023 with MongoDB Community 7.0
- **TLS Certificates:** Custom CA and server certificates for MongoDB

### Teleport Resources
- **Provision Token:** For database and SSH service registration
- **Database Users:** `writer` and `reader` with certificate authentication in `$external` database

### Teleport Services Enabled
- ** Database Service:** MongoDB database access with certificate auth
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
  compliance  = "gdpr"           # Add compliance requirements
}
```

## Demo Commands

### Database Access
```bash
# List databases
tsh db ls --labels=tier=dev

# Connect as reader
tsh db connect mongodb-dev --db-user=reader

# Connect as writer
tsh db connect mongodb-dev --db-user=writer

# Show databases (in MongoDB shell)
show dbs

# Test permissions (reader vs writer)
use testdb
db.testcol.insertOne({name: "test"})  # Will fail for reader
db.testcol.find()                     # Works for both (if data exists)
```

### SSH Access (Server Management)
```bash
# List SSH nodes
tsh ls --labels=tier=dev

# SSH into the database server
tsh ssh ec2-user@dev-mongodb

# Check MongoDB status
sudo systemctl status mongod

# View MongoDB logs
sudo tail -f /var/log/mongodb/mongod.log

# Check database connections
mongosh --tls --tlsCAFile /etc/certs/mongo.cas \
        --tlsCertificateKeyFile /etc/certs/mongo.crt \
        --eval "db.serverStatus().connections"
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment name | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `teleport_db_ca` | Teleport DB CA certificate | `string` | - |
| `mongodb_hostname` | Hostname for TLS certificate | `string` | `"mongodb.example.internal"` |
| `ami_id` | AMI ID for instance | `string` | - |
| `instance_type` | EC2 instance type | `string` | - |
| `subnet_id` | Subnet for instance | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label | `string` | `"engineering"` |

## Outputs

| Output | Description |
|--------|-------------|
| `ca_cert` | Custom CA certificate used for MongoDB TLS |

## Security Features

- **Mutual TLS:** All database connections use client certificates
- **Certificate Authentication:** Users authenticate via X.509 certificates (CN-based)
- **TLS Required:** MongoDB configured to require TLS for all connections
- **Custom CA:** Self-signed CA for demonstration purposes
- **Authorization Enabled:** MongoDB auth enabled with role-based access

## Database Users

| User | Location | Permissions | Use Case |
|------|----------|-------------|----------|
| `CN=writer` | `$external` | `readWriteAnyDatabase`, `dbAdminAnyDatabase` | Administrative tasks, data modification |
| `CN=reader` | `$external` | `readAnyDatabase` | Read-only access across all databases |
| `admin` | `admin` | `root` | Local admin user (for initial setup) |

## MongoDB Configuration

### TLS Configuration
```yaml
# Key MongoDB settings applied:
net:
  port: 27017
  bindIp: 0.0.0.0
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/certs/mongo.crt
    CAFile: /etc/certs/mongo.cas
    allowConnectionsWithoutCertificates: false

security:
  authorization: enabled
```

### Authentication Flow
1. **Certificate Validation:** MongoDB validates client certificate against CA
2. **User Mapping:** Certificate CN maps to user in `$external` database
3. **Role Assignment:** Predefined roles grant appropriate permissions

## Integration

This module is designed to work with the `registration` module:

```hcl
module "mongodb_registration" {
  source        = "../../modules/registration"
  resource_type = "database"
  name          = "mongodb-${var.env}"
  protocol      = "mongodb"
  uri           = "localhost:27017"
  ca_cert_chain = module.mongodb_instance.ca_cert
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
tsh ssh ec2-user@dev-mongodb

# Check all Teleport services
sudo systemctl status teleport
sudo journalctl -u teleport -f

# Check MongoDB service
sudo systemctl status mongod
sudo tail -f /var/log/mongodb/mongod.log

# Test database connectivity with TLS
mongosh --tls --tlsCAFile /etc/certs/mongo.cas \
        --tlsCertificateKeyFile /etc/certs/mongo.crt \
        --eval "db.runCommand({hello: 1})"
```

### Common Issues
- **Database Connection Failed:** Check TLS certificates and MongoDB status
- **SSH Access Denied:** Verify user roles and node labels
- **Certificate Errors:** Ensure Teleport DB CA and MongoDB CA are properly configured
- **TLS Connection Required:** All connections must use TLS
- **Authentication Failed:** Check certificate CN matches user in `$external` database
- **Storage Engine Issues:** MongoDB may fail to start if storage is corrupted

### Service-Specific Debugging
```bash
# Database service issues
tsh db ls --debug
tctl db ls

# SSH service issues  
tsh ls --debug
tctl nodes ls

# MongoDB TLS debugging
mongosh --tls --tlsCAFile /etc/certs/mongo.cas \
        --tlsCertificateKeyFile /etc/certs/mongo.crt \
        --eval "db.runCommand({serverStatus: 1}).connections"

# Check MongoDB users and roles
mongosh --tls --tlsCAFile /etc/certs/mongo.cas \
        --tlsCertificateKeyFile /etc/certs/mongo.crt \
        --eval "db.getSiblingDB('\$external').runCommand({usersInfo: 1})"
```

### Bootstrap Issues
MongoDB has a complex initialization process. If issues occur:

```bash
# Check initialization logs
sudo tail -f /var/log/cloud-init-output.log

# Manual MongoDB restart
sudo systemctl stop mongod
sudo systemctl start mongod

# Check certificate permissions
ls -la /etc/certs/
sudo chown -R mongod:mongod /etc/certs/

# Verify MongoDB configuration
sudo cat /etc/mongod.conf
```

## Features

- **MongoDB 7.0:** Latest stable community version
- **X.509 Authentication:** Certificate-based user authentication via CN mapping
- **TLS Encryption:** All connections encrypted with custom CA
- **Enhanced Recording:** Database session recording via Teleport
- **Dual Service Access:** Both database and SSH access for complete management
- **Configurable Hostname:** Custom hostname for TLS certificate
- **Role-based Access:** Granular permissions via MongoDB roles

## Performance Considerations

- **TLS Overhead:** TLS adds performance overhead, monitor connection latency
- **Certificate Authentication:** CN-based auth is efficient but requires proper certificate management
- **Storage Engine:** Using WiredTiger (default) for better performance
- **Connection Limits:** Monitor concurrent connections via `db.serverStatus().connections`
- **Memory Usage:** MongoDB uses available RAM for caching, size instances appropriately

## Advanced Configuration

### Custom User Creation
```javascript
// Connect as admin to create additional users
use admin
db.auth("admin", "admin123")

// Create custom user in $external database
db.getSiblingDB("$external").runCommand({
  createUser: "CN=developer",
  roles: [
    { role: "readWrite", db: "myapp" },
    { role: "read", db: "analytics" }
  ]
})
```

### Connection String Examples
```bash
# Teleport connection (preferred)
tsh db connect mongodb-dev --db-user=reader

# Direct connection (for debugging)
mongosh "mongodb://localhost:27017/?tls=true&tlsCAFile=/etc/certs/mongo.cas&tlsCertificateKeyFile=/etc/certs/mongo.crt&authMechanism=MONGODB-X509"
```