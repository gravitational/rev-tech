# RDS MySQL Module

This module creates an RDS MySQL instance with direct IAM authentication for Teleport auto user provisioning, along with a Teleport agent configured to connect to the database.

## Features

- **Direct RDS Access**: Connects directly to RDS without proxy
- **IAM Authentication**: Uses AWS IAM for database authentication
- **Auto User Provisioning**: Automatically creates database users based on Teleport roles
- **TLS Required**: Enforces secure transport for all connections
- **Integrated Agent**: Includes EC2 instance with Teleport agent pre-configured

## Usage

```hcl
module "rds_mysql" {
  source = "../../modules/rds_mysql"

  env                   = "dev"
  user                  = "engineer@company.com"
  proxy_address         = "teleport.company.com"
  teleport_version      = "17.5.2"
  region                = "us-east-2"
  vpc_id                = module.network.vpc_id
  db_subnet_group_name  = module.network.db_subnet_group_name
  subnet_id             = module.network.public_subnet_id
  security_group_ids    = [module.network.security_group_id]
  ami_id                = data.aws_ami.ubuntu.id
}
```

## What It Creates

### AWS Resources
- **RDS MySQL Instance**: MySQL 8.0 with IAM authentication enabled
- **DB Parameter Group**: Configured with `require_secure_transport=ON`
- **Security Group**: Allows MySQL connections from Teleport agent
- **IAM Role & Policy**: Grants RDS connect permissions to EC2 instance
- **EC2 Instance**: Teleport agent with database service enabled (Amazon Linux 2023)

### Teleport Resources
- **Provision Token**: Short-lived token for agent registration
- **Database Resource**: Registered in Teleport with auto user provisioning
- **Agent Configuration**: Pre-configured for database and SSH services

## Database Configuration

The module automatically configures the RDS instance for Teleport:

1. **Admin User**: Creates `teleport-admin` with `AWSAuthenticationPlugin`
2. **Permissions**: Grants necessary permissions for user provisioning
3. **Database**: Creates `teleport` database for Teleport operations

## Auto User Provisioning

Users are automatically created on first connection based on their Teleport roles:
- Users get permissions based on their Teleport role mappings
- No manual database user management required
- Supports dynamic user creation and cleanup

## Security Features

- **TLS Required**: All connections must use TLS
- **IAM Authentication**: Database authentication through AWS IAM
- **Encrypted Storage**: RDS storage is encrypted at rest
- **VPC Security**: Database isolated in private subnets
- **Least Privilege**: IAM policy grants minimum required permissions

## Connection Example

```bash
# Login to Teleport
tsh login --proxy=teleport.company.com

# List available databases
tsh db ls

# Connect to the database
tsh db connect rds-mysql-dev

# Auto user provisioning will create your database user automatically
```

## Extending for Other RDS Types

This module can be extended for other RDS engines:
- PostgreSQL: Similar pattern with different engine/port
- SQL Server: Requires different IAM authentication approach
- Oracle: Similar to MySQL but different configuration

## Troubleshooting

### Common Issues

1. **Connection Timeout**: Check security group rules and VPC configuration
2. **IAM Authentication Failed**: Verify IAM role has `rds-db:connect` permission
3. **TLS Errors**: Ensure `require_secure_transport=ON` in parameter group
4. **User Creation Failed**: Check `teleport-admin` user permissions

### Debugging

- Check EC2 instance logs: `/var/log/cloud-init-output.log`
- Verify RDS status: `aws rds describe-db-instances`
- Test database connection: `mysql -h <endpoint> -u admin -p`
- Check Teleport agent logs: `journalctl -u teleport`