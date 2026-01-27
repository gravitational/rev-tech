# Machine ID Host Module

A utility module for creating Teleport Machine ID bots and associated roles for automated infrastructure access. This module provides the foundational identity infrastructure for machine-to-machine authentication.

## Overview

- **Use Case:** Machine identity creation for automation and CI/CD
- **Teleport Features:** Machine ID (bot) creation, role-based machine access, token management
- **Infrastructure:** Creates only Teleport resources - no AWS infrastructure

## Usage

```hcl
module "host_identity" {
  source = "../../modules/machineid-host"
  
  env              = "dev"
  user             = "engineer@company.com"
  proxy_address    = "teleport.company.com"
  teleport_version = "17.5.2"
  
  bot_name       = "automation-bot"
  role_name      = "automation-role"
  allowed_logins = ["ec2-user", "ubuntu", "deploy"]
  node_labels = {
    tier = ["dev", "staging"]
    team = ["engineering"]
    service = ["web", "api"]
  }
}
```

## What It Creates

### Teleport Resources Only
- **Bot Identity:** Machine ID bot for automated authentication
- **Bot Role:** Custom role defining bot permissions
- **Provision Token:** Short-lived token for bot registration

### No AWS Resources
This module creates only Teleport identities and roles - no EC2 instances or other AWS infrastructure.

## Bot Identity & Role Structure

This module creates machine identities with specific access patterns:

```yaml
Bot Configuration:
  name: "automation-bot"                    # From var.bot_name
  token: "{random-32-char-string}"          # Auto-generated secure token
  roles: ["automation-role"]                # Custom role created by module

Role Permissions:
  allow:
    logins: ["ec2-user", "ubuntu"]          # System users bot can access
    node_labels:
      tier: ["dev", "staging"]              # Environment access
      team: ["engineering"]                 # Team restrictions
```

### RBAC Integration
```yaml
# Role created by this module:
{role_name}:
  version: v7
  allow:
    logins: {allowed_logins}
    node_labels: {node_labels}

# How this integrates with human access:
human-role:
  allow:
    # Humans can manage nodes with same labels
    node_labels: 
      tier: ["dev", "staging"]
      team: ["engineering"]
    # But bots have more restricted login access
```

### Customization for Different Use Cases
```hcl
# CI/CD Bot - Deployment focused
module "ci_bot" {
  source = "../../modules/machineid-host"
  bot_name = "ci-deployment"
  role_name = "ci-deployment-role"
  allowed_logins = ["deploy", "app"]
  node_labels = {
    tier = ["staging", "prod"]
    service = ["api", "web"]
  }
}

# Monitoring Bot - Read-only access
module "monitoring_bot" {
  source = "../../modules/machineid-host"
  bot_name = "monitoring"
  role_name = "monitoring-role"  
  allowed_logins = ["monitoring", "prometheus"]
  node_labels = {
    tier = ["*"]            # Access all environments
    team = ["sre"]          # SRE team only
  }
}

# Backup Bot - Specific service access
module "backup_bot" {
  source = "../../modules/machineid-host"
  bot_name = "backup-agent"
  role_name = "backup-role"
  allowed_logins = ["backup"]
  node_labels = {
    tier = ["prod"]
    service = ["database"]
    backup_enabled = ["true"]
  }
}
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version (for compatibility) | `string` | - |
| `user` | Creator tag | `string` | - |
| `bot_name` | Name of the Machine ID bot | `string` | `"ansible"` |
| `role_name` | Name of the Teleport role to create | `string` | - |
| `allowed_logins` | System users bot can access | `list(string)` | - |
| `node_labels` | Node labels the role should access | `map(list(string))` | - |

## Outputs

| Output | Description |
|--------|-------------|
| `bot_token` | Token used by tbot for Machine ID authentication |
| `bot_name` | Name of the created bot |
| `role_id` | Terraform resource ID of the created role |

## Integration Patterns

### With Infrastructure Modules
```hcl
# 1. Create bot identity
module "host_identity" {
  source = "../../modules/machineid-host"
  bot_name = "ansible"
  role_name = "ansible-machine-role"
  allowed_logins = ["ec2-user"]
  node_labels = {
    tier = ["dev"]
    team = ["engineering"]
  }
}

# 2. Use bot token in automation infrastructure
module "ansible_server" {
  source = "../../modules/machineid_ansible"
  # Bot token passed internally via module integration
}
```

### Standalone Bot Creation
```hcl
# Create bot for external CI/CD system
module "ci_bot" {
  source = "../../modules/machineid-host"
  bot_name = "github-actions"
  role_name = "ci-deployment-role"
  allowed_logins = ["deploy", "app"]
  node_labels = {
    tier = ["staging", "prod"]
    service = ["api", "frontend"]
  }
}

# Extract token for external use
output "ci_bot_token" {
  value = module.ci_bot.bot_token
  sensitive = true
}
```

## Bot Token Management

### Token Security
```bash
# Bot tokens are:
- 32 characters long with special characters
- Valid for 1 hour (short-lived)
- Used only for initial bot registration
- Replaced by certificates after first use
```

### Token Usage Pattern
```bash
# 1. Terraform creates bot and token
# 2. Token passed to tbot for initial authentication
# 3. tbot exchanges token for certificates
# 4. Certificates auto-renew, token no longer needed
```

## Role-Based Access Examples

### Environment-Based Access
```hcl
# Development bot - limited access
dev_bot_labels = {
  tier = ["dev"]
  team = ["engineering"]
}

# Production bot - broader but controlled access  
prod_bot_labels = {
  tier = ["staging", "prod"]
  team = ["platform", "sre"]
  compliance = ["audited"]
}
```

### Service-Based Access
```hcl
# Web tier access
web_bot_labels = {
  service = ["web", "frontend", "cdn"]
  tier = ["*"]
}

# Database access
db_bot_labels = {
  service = ["database", "cache"]
  tier = ["prod"]
  backup_required = ["true"]
}
```

### Geographic Access
```hcl
# Regional bot access
regional_bot_labels = {
  region = ["us-west-2", "us-east-1"]
  tier = ["prod"]
  disaster_recovery = ["enabled"]
}
```

## Demo Commands

### Bot Verification
```bash
# Check bot creation
tctl get bot/{bot_name}
tctl get role/{role_name}

# List all bots
tctl get bots

# Check bot permissions
tctl get role/{role_name} -o yaml
```

### Token Management  
```bash
# List provision tokens
tctl tokens ls

# Check token details (if still valid)
tctl get token/{token_name}

# Note: Tokens expire after 1 hour and aren't needed after bot registration
```

### Role Testing
```bash
# Test role permissions (as human with admin access)
tctl auth sign --format=openssh --user={bot_name} --role={role_name}

# Verify node access with bot role
tsh ls --labels="tier=dev,team=engineering"
```

## Troubleshooting

### Bot Creation Issues
```bash
# Check if bot was created successfully
tctl get bot/{bot_name}

# Verify role exists and has correct permissions
tctl get role/{role_name}
tctl get role/{role_name} -o yaml

# Check Terraform state
terraform state show module.{module_name}.teleport_bot.host
terraform state show module.{module_name}.teleport_role.machine
```

### Token Issues
```bash
# Check if token is still valid (they expire quickly)
tctl tokens ls

# If token expired, re-run terraform apply to generate new token
terraform apply -target=module.{module_name}.teleport_provision_token.bot

# Check token permissions
tctl get token/{token_name} -o yaml
```

### Role Permission Issues
```bash
# Debug role permissions
tctl get role/{role_name} -o yaml

# Test what nodes the role can access
tctl auth sign --format=openssh --user={bot_name} --role={role_name}

# Check if target nodes have the required labels
tctl get nodes --labels="tier=dev,team=engineering"
```

### Common Issues
- **Bot Not Found:** Check Terraform apply completed successfully
- **Token Expired:** Re-run terraform apply to generate new token
- **Access Denied:** Verify node labels match role requirements
- **Role Not Applied:** Check bot configuration includes the correct role

## Features

- **Flexible Access Control:** Granular control via node labels
- **Short-lived Tokens:** Secure token management with 1-hour expiry
- **Role Reusability:** Roles can be used by multiple bots
- **Label-based Discovery:** Dynamic access based on resource labels
- **Terraform Managed:** Complete infrastructure-as-code approach

## Security Best Practices

### Token Security
```bash
# 1. Tokens expire after 1 hour
# 2. Store tokens securely (Terraform state, CI/CD secrets)
# 3. Rotate tokens by re-running Terraform
# 4. Monitor token usage in Teleport audit logs
```

### Role Design
```hcl
# 1. Principle of least privilege
allowed_logins = ["deploy"]  # Only necessary users

# 2. Environment separation  
node_labels = {
  tier = ["dev"]             # Avoid wildcard access
  team = ["engineering"]     # Limit to specific teams
}

# 3. Service-specific access
node_labels = {
  service = ["api"]          # Limit to specific services
}
```

### Bot Naming
```bash
# Use descriptive bot names
bot_name = "ci-deployment"     # Clear purpose
bot_name = "monitoring-agent"  # Clear function
bot_name = "backup-service"    # Clear role

# Avoid generic names
bot_name = "bot1"              # Too generic
bot_name = "automation"        # Too broad
```

## Advanced Use Cases

### Multi-Environment Bots
```hcl
# Bot with staging and production access
module "deployment_bot" {
  source = "../../modules/machineid-host"
  bot_name = "deployment"
  role_name = "deployment-role"
  allowed_logins = ["deploy", "app"]
  node_labels = {
    tier = ["staging", "prod"]
    service = ["api", "web", "worker"]
    deployment_target = ["true"]
  }
}
```

### Specialized Service Bots
```hcl
# Database maintenance bot
module "db_maintenance_bot" {
  source = "../../modules/machineid-host"
  bot_name = "db-maintenance"
  role_name = "db-maintenance-role"
  allowed_logins = ["postgres", "mysql", "mongodb"]
  node_labels = {
    service = ["database"]
    maintenance_window = ["allowed"]
  }
}
```

### Cross-Team Access
```hcl
# SRE bot with cross-team access
module "sre_bot" {
  source = "../../modules/machineid-host"
  bot_name = "sre-operations"
  role_name = "sre-operations-role"
  allowed_logins = ["sre", "monitoring"]
  node_labels = {
    tier = ["*"]                    # All environments
    team = ["engineering", "platform", "data"]  # Multiple teams
    sre_managed = ["true"]
  }
}
```