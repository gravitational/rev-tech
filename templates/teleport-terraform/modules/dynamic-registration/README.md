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
  source = "../../modules/registration"
  
  resource_type = "database"
  name          = "mysql-dev"
  description   = "Self-hosted MySQL database for dev environment"
  protocol      = "mysql"
  uri           = "localhost:3306"
  ca_cert_chain = module.mysql_instance.ca_cert
  
  labels = {
    tier = "dev"
    team = "engineering"
  }
}
```

### Application Registration
```hcl
module "grafana_registration" {
  source = "../../modules/registration"
  
  resource_type = "app"
  name          = "grafana-dev"
  description   = "Grafana dashboard for dev environment"
  uri           = "http://localhost:3000"
  public_addr   = "grafana-dev.teleport.company.com"
  
  labels = {
    tier               = "dev"
    team               = "engineering"
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
  tier: "dev"                    # Environment-based access
  team: "engineering"            # Team-based access
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
    tier: ["dev", "staging"]     # Access specific environments
    team: ["engineering"]        # Team-based restrictions
  app_labels:
    tier: ["dev"]
    "teleport.dev/app": ["grafana", "kibana"]  # Specific applications
```

### Customization for Your Environment
```hcl
# Adapt labels for organizational needs:
labels = {
  # Environment classification
  tier        = "production"     # dev, staging, prod
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
| `uri` | Connection URI (host:port for DB, full URL for apps) | `string` | - |
| `ca_cert_chain` | CA certificate chain in PEM format (database only) | `string` | `""` |
| `public_addr` | Public address for application access (app only) | `string` | `null` |
| `labels` | Labels to apply to the resource | `map(string)` | - |
| `rewrite_headers` | HTTP headers to rewrite (app only) | `list(string)` | `[]` |
| `insecure_skip_verify` | Skip TLS verification (app only) | `bool` | `false` |

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
  source = "../../modules/postgres_instance"
  # ... configuration
}

# 2. Register with Teleport
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

### Application + Registration Pattern
```hcl
# 1. Create application infrastructure
module "httpbin_app" {
  source = "../../modules/app_httpbin"
  # ... configuration
}

# 2. Register with Teleport
module "httpbin_registration" {
  source        = "../../modules/registration"
  resource_type = "app"
  name          = "httpbin-${var.env}"
  uri           = "http://localhost:80"
  public_addr   = "httpbin-${var.env}.${var.proxy_address}"
  labels = {
    tier               = var.env
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
  tier        = var.env
  team        = var.team
  
  # Service discovery
  "teleport.dev/app" = "grafana"
  
  # Business context
  cost_center = "engineering"
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
tctl get db --labels=tier=dev
tctl get app --labels=team=engineering
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
tsh db ls --labels=tier=dev
tsh apps ls --labels=tier=dev

# Verify Terraform state
terraform state show module.mysql_registration.teleport_database.this[0]
```

## Best Practices

1. **Consistent Labeling:** Use the same label structure across all environments
2. **Descriptive Names:** Include environment in resource names (`mysql-dev`, `grafana-prod`)
3. **Proper TLS:** Always provide CA certificates for database resources
4. **Header Rewriting:** Configure proper headers for subdomain application access
5. **Team Ownership:** Always include team labels for accountability