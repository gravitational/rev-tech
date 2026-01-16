# RDS MySQL with Auto User Provisioning

This example provisions an RDS MySQL database with direct IAM authentication and demonstrates Teleport's auto user provisioning capabilities.

It follows the official [Auto User Provisioning for MySQL guide](https://goteleport.com/docs/enroll-resources/database-access/auto-user-provisioning/mysql/) and uses direct RDS access (not RDS Proxy).

---

## What It Deploys

- **RDS MySQL 8.0** with IAM authentication enabled
- **Teleport agent** on EC2 (Amazon Linux 2023) with database service configured
- **Auto user provisioning** - users created automatically on first connection
- **TLS enforcement** - all connections require secure transport
- **IAM-based authentication** - uses AWS IAM for database access

---

## Usage

### 1. Set Environment Variables

```bash
export TF_VAR_user="engineer@company.com"
export TF_VAR_proxy_address="teleport.company.com"
export TF_VAR_teleport_version="17.5.2"
export TF_VAR_region="us-east-2"
export TF_VAR_env="dev"
```

### 2. Authenticate to Teleport

```bash
tsh login --proxy=$TF_VAR_proxy_address
eval $(tctl terraform env)
```

### 3. Deploy

```bash
cd data_plane/rds_mysql
terraform init
terraform apply
```

### 4. Test Database Access

```bash
# List available databases
tsh db ls

# Connect to the database
tsh db connect rds-mysql-dev

# Your database user will be created automatically based on your Teleport roles
```

---

## Auto User Provisioning

This example demonstrates Teleport's auto user provisioning:

1. **Admin User**: `teleport-admin` with IAM authentication
2. **Automatic Creation**: Users created on first connection
3. **Role-based Permissions**: Database permissions based on Teleport roles
4. **No Manual Management**: No need to pre-create database users

### Example User Creation

When a user with the `dev-access` role connects:
- Database user is automatically created
- Permissions granted based on role configuration
- User can immediately start working with the database

---

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Teleport      │    │   EC2 Agent     │    │   RDS MySQL     │
│   Cluster       │◄──►│   (db_service)  │◄──►│   (IAM Auth)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                               │
                               ▼
                       ┌─────────────────┐
                       │   IAM Role      │
                       │   (rds-db:      │
                       │    connect)     │
                       └─────────────────┘
```

---

## Key Differences from RDS Proxy

| Feature | RDS Proxy | Direct RDS |
|---------|-----------|------------|
| **Auto User Provisioning** | ❌ Not supported | ✅ Supported |
| **IAM Authentication** | ✅ Supported | ✅ Supported |
| **Connection Pooling** | ✅ Built-in | ❌ Not available |
| **Complexity** | Higher | Lower |
| **Use Case** | High-connection apps | Teleport access |

---

## Extending to Other RDS Types

This module can be extended for other RDS engines:

### PostgreSQL
```hcl
# Similar configuration, different engine
engine         = "postgres"
engine_version = "15.4"
port           = 5432
```

### SQL Server
```hcl
# Requires different IAM authentication approach
engine         = "sqlserver-ex"
engine_version = "15.00"
port           = 1433
```

---

## Clean Up

```bash
terraform destroy
```

---

## Notes

- Uses direct RDS access for auto user provisioning support
- IAM authentication provides secure, credential-free database access
- TLS is enforced for all database connections
- Users are automatically managed based on Teleport roles
- Perfect for development and testing environments