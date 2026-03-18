# Registration Module

A utility module for registering databases and applications with Teleport using dynamic resource creation. Provides consistent resource registration across all demo modules.

## Overview

- **Use Case:** Centralized Teleport resource registration utility
- **Teleport Features:** Dynamic resource discovery, label-based access control
- **Infrastructure:** Creates `teleport_database` or `teleport_app` resources via Terraform

## Usage

### Database Registration
```hcl
module "mysql_registration" {
  source = "../../modules/dynamic-registration"
  
  resource_type = "database"
  name          = "mysql-dev"
  description   = "Self-hosted MySQL database for dev environment"
  protocol      = "mysql"
  uri           = "localhost:3306"
  ca_cert_chain = module.mysql_instance.ca_cert
  
  labels = {
    env = "dev"
    team = "platform"
  }
}
```

### Application Registration
```hcl
module "grafana_registration" {
  source = "../../modules/dynamic-registration"
  
  resource_type = "app"
  name          = "grafana-dev"
  description   = "Grafana dashboard for dev environment"
  uri           = "http://localhost:3000"
  public_addr   = "grafana-dev.teleport.company.com"
  
  labels = {
    env               = "dev"
    team               = "platform"
    "teleport.dev/app" = "grafana"
  }
  
  rewrite_headers = [
    "Host: grafana-dev.teleport.company.com",
    "Origin: https://grafana-dev.teleport.company.com"
  ]
  
  insecure_skip_verify = true
}
```

## What It Creates

### Teleport Resources
- **Database Resource:** `teleport_database` for database access (when `resource_type = "database"`)
- **Application Resource:** `teleport_app` for application access (when `resource_type = "app"`)

### No AWS Resources
This module only creates Teleport resources via the Terraform provider - no AWS infrastructure.

## Label Structure & Access Control

This module standardizes label application across all resources:

```yaml
Standard Labels Applied:
  env: "dev"                    # Environment-based access
  team: "platform"            # Team-based access
  "teleport.dev/origin": "dynamic"  # Indicates Terraform-managed

Additional Labels (context-specific):
  "teleport.dev/app": "grafana"  # Application type for discovery
  environment: "production"      # Custom organizational labels
  compliance: "pci"             # Compliance classifications
```

### RBAC Integration
```yaml
# Example Teleport roles using registered resources:
allow:
  db_labels:
    env: ["dev", "staging"]     # Access specific environments
    team: ["platform"]        # Team-based restrictions
  app_labels:
    env: ["dev"]
    "teleport.dev/app": ["grafana", "kibana"]  # Specific applications
```

### Customization for Your Environment
```hcl
# Adapt labels for organizational needs:
labels = {
  # Environment classification
  env        = "production"     # dev, staging, prod
  environment = "us-west-2"      # Regional classification
  
  # Organizational structure  
  team        = "platform"       # team ownership
  squad       = "sre"            # sub-team ownership
  
  # Compliance and security
  compliance  = "sox"            # compliance requirements
  criticality = "high"           # business criticality
  
  # Service discovery (apps only)
  "teleport.dev/app" = "grafana"
}
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `resource_type` | Type of resource ("database" or "app") | `string` | `"database"` |
| `name` | Name of the Teleport resource | `string` | - |
| `description` | Description for the resource | `string` | `""` |
| `protocol` | Protocol (database only: mysql, postgres, mongodb) | `string` | `""` |
| `uri` | Connection URI (host:port for DB, URL for web apps, optional for MCP stdio apps) | `string` | `null` |
| `ca_cert_chain` | CA certificate chain in PEM format (database only) | `string` | `""` |
| `public_addr` | Public address for application access (app only) | `string` | `null` |
| `labels` | Labels to apply to the resource | `map(string)` | - |
| `rewrite_headers` | HTTP headers to rewrite (app only) | `list(string)` | `[]` |
| `insecure_skip_verify` | Skip TLS verification (app only) | `bool` | `false` |
| `mcp_command` | Optional MCP stdio command (app only) | `string` | `null` |
| `mcp_args` | Optional MCP stdio command args (app only) | `list(string)` | `[]` |
| `mcp_run_as_host_user` | Optional host user for MCP stdio command | `string` | `null` |
| `app_aws_external_id` | Optional `spec.aws.external_id` for AWS Console apps | `string` | `null` |

## Outputs

| Output | Description |
|--------|-------------|
| `resource_name` | Name of the created resource |
| `resource_type` | Type of resource created |
| `resource_id` | Terraform resource ID |

## Resource Types

### Database Resources
**Supported protocols:**
- `mysql` - MySQL/MariaDB databases
- `postgres` - PostgreSQL databases  
- `mongodb` - MongoDB databases

**Required for databases:**
- `protocol` - Database type
- `uri` - Connection string (host:port)
- `ca_cert_chain` - TLS CA certificate

### Application Resources
**Supported application types:**
- Web applications with HTTP/HTTPS access
- Applications requiring JWT authentication
- Applications needing header rewriting

**Required for applications:**
- `uri` - Internal application URL
- `public_addr` - External access URL

## Integration Patterns

### Database + Registration Pattern
```hcl
# 1. Create database infrastructure
module "postgres_instance" {
  source = "../../modules/self-postgres"
  # ... configuration
}

# 2. Register with Teleport
module "postgres_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "database"
  name          = "postgres-${var.env}"
  protocol      = "postgres"
  uri           = "localhost:5432"
  ca_cert_chain = module.postgres_instance.ca_cert
  labels = {
    env = var.env
    team = var.team
  }
}
```

### Application + Registration Pattern
```hcl
# 1. Create application infrastructure
module "httpbin_app" {
  source = "../../modules/app-httpbin"
  # ... configuration
}

# 2. Register with Teleport
module "httpbin_registration" {
  source        = "../../modules/dynamic-registration"
  resource_type = "app"
  name          = "httpbin-${var.env}"
  uri           = "http://localhost:80"
  public_addr   = "httpbin-${var.env}.${var.proxy_address}"
  labels = {
    env               = var.env
    team               = var.team
    "teleport.dev/app" = "httpbin"
  }
  insecure_skip_verify = true
}
```

## Advanced Configuration

### Header Rewriting for Applications
```hcl
# Complex header rewriting for subdomain applications
rewrite_headers = [
  "Host: myapp-${var.env}.${var.proxy_address}",
  "Origin: https://myapp-${var.env}.${var.proxy_address}",
  "X-Forwarded-Proto: https",
  "X-Forwarded-Host: myapp-${var.env}.${var.proxy_address}"
]
```

### Complex Label Structures
```hcl
# Comprehensive labeling for enterprise environments
labels = {
  # Access control
  env        = var.env
  team        = var.team
  
  # Service discovery
  "teleport.dev/app" = "grafana"
  
  # Business context
  cost_center = "platform"
  project     = "observability"
  
  # Compliance
  data_classification = "internal"
  backup_required     = "true"
  
  # Operational
  monitoring_team = "sre"
  on_call_group   = "platform"
}
```

## Troubleshooting

### Resource Registration Issues
```bash
# Check if resources are properly registered
tctl db ls | grep mysql-dev
tctl apps ls | grep grafana-dev

# Verify resource configuration
tctl get db/mysql-dev
tctl get app/grafana-dev

# Check labels are applied correctly
tctl get db --labels=env=dev
tctl get app --labels=team=platform
```

### Common Issues
- **Resource Not Found:** Check Terraform apply completed successfully
- **Access Denied:** Verify user roles include the resource labels
- **Certificate Issues:** Ensure CA certificate is properly formatted
- **Header Rewriting Failed:** Check header syntax and public_addr configuration

### Debug Commands
```bash
# List all resources with labels
tctl get db --labels="*"
tctl get app --labels="*"

# Test resource access
tsh db ls env=dev
tsh apps ls env=dev

# Verify Terraform state
terraform state show module.mysql_registration.teleport_database.this[0]
```

## Best Practices

1. **Consistent Labeling:** Use the same label structure across all environments
2. **Descriptive Names:** Include environment in resource names (`mysql-dev`, `grafana-prod`)
3. **Proper TLS:** Always provide CA certificates for database resources
4. **Header Rewriting:** Configure proper headers for subdomain application access
5. **Team Ownership:** Always include team labels for accountability
