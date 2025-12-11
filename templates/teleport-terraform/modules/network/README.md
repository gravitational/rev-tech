# Network Module

Creates foundational AWS networking infrastructure including VPC, subnets, security groups, and NAT gateway for Teleport demo environments.

## Overview

- **Use Case:** Foundational networking for all Teleport demos
- **Teleport Features:** Secure network foundation for all Teleport services
- **Infrastructure:** VPC, public/private subnets, NAT gateway, security groups, optional DB subnet group

## Usage

```hcl
module "network" {
  source = "../../modules/network"
  
  env                     = "dev"
  cidr_vpc               = "10.0.0.0/16"
  cidr_subnet            = "10.0.1.0/24"    # Private subnet
  cidr_public_subnet     = "10.0.0.0/24"    # Public subnet
  
  # Optional: For RDS deployments
  create_secondary_subnet = true
  cidr_secondary_subnet  = "10.0.2.0/24"    # Second private subnet
  create_db_subnet_group = true
}
```

## What It Creates

### AWS Resources
- **VPC:** Main virtual private cloud with DNS enabled
- **Public Subnet:** For resources needing direct internet access
- **Private Subnet:** For secure resources (databases, internal services)
- **Secondary Private Subnet:** (Optional) For RDS multi-AZ deployments
- **Internet Gateway:** For public internet access
- **NAT Gateway:** For private subnet outbound internet access
- **Route Tables:** Proper routing for public and private subnets
- **Security Group:** Default security group allowing VPC internal traffic
- **DB Subnet Group:** (Optional) For RDS database deployments

### Network Architecture
```
Internet Gateway
       |
   Public Subnet (10.0.0.0/24)
       |
   NAT Gateway
       |
Private Subnet (10.0.1.0/24) --> Resources (Teleport agents)
       |
Secondary Private Subnet (10.0.2.0/24) --> RDS (if enabled)
```

## Security Configuration

### Default Security Group Rules
```yaml
Ingress:
  - Port: 0-65535
    Protocol: TCP
    Source: VPC CIDR (10.0.0.0/16)
    
Egress:
  - Port: 0-65535
    Protocol: All
    Destination: 0.0.0.0/0 (Internet)
```

### Network Isolation
- **Public Subnet:** Resources with direct internet access (bastion hosts, load balancers)
- **Private Subnets:** Secure resources communicating through NAT gateway
- **Inter-subnet Communication:** Allowed within VPC CIDR block

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment name for tagging | `string` | - |
| `cidr_vpc` | CIDR block for the VPC | `string` | - |
| `cidr_subnet` | CIDR block for private subnet | `string` | - |
| `cidr_public_subnet` | CIDR block for public subnet | `string` | - |
| `create_secondary_subnet` | Create second private subnet for RDS | `bool` | `false` |
| `cidr_secondary_subnet` | CIDR block for secondary private subnet | `string` | `""` |
| `create_db_subnet_group` | Create DB subnet group for RDS | `bool` | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the created VPC |
| `subnet_id` | ID of the primary private subnet |
| `public_subnet_id` | ID of the public subnet |
| `private_subnet_ids` | List of all private subnet IDs |
| `security_group_id` | ID of the default security group |
| `db_subnet_group_name` | Name of the DB subnet group (if created) |

## Integration Examples

### Basic Teleport Resources
```hcl
module "network" {
  source             = "../../modules/network"
  env                = "dev"
  cidr_vpc           = "10.0.0.0/16"
  cidr_subnet        = "10.0.1.0/24"
  cidr_public_subnet = "10.0.0.0/24"
}

module "ssh_nodes" {
  source             = "../../modules/ssh_node"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
  # ... other variables
}
```

### With RDS Database
```hcl
module "network" {
  source                  = "../../modules/network"
  env                     = "dev"
  cidr_vpc               = "10.0.0.0/16"
  cidr_subnet            = "10.0.1.0/24"
  cidr_public_subnet     = "10.0.0.0/24"
  create_secondary_subnet = true
  cidr_secondary_subnet  = "10.0.2.0/24"
  create_db_subnet_group = true
}

module "rds_mysql" {
  source               = "../../modules/rds_mysql"
  vpc_id               = module.network.vpc_id
  db_subnet_group_name = module.network.db_subnet_group_name
  # ... other variables
}
```

## CIDR Planning

### Recommended CIDR Schemes

**Small Environment (dev/testing):**
```hcl
cidr_vpc              = "10.0.0.0/16"    # 65,536 IPs
cidr_public_subnet    = "10.0.0.0/24"    # 256 IPs
cidr_subnet           = "10.0.1.0/24"    # 256 IPs  
cidr_secondary_subnet = "10.0.2.0/24"    # 256 IPs
```

**Medium Environment (staging/prod):**
```hcl
cidr_vpc              = "10.0.0.0/16"     # 65,536 IPs
cidr_public_subnet    = "10.0.0.0/20"     # 4,096 IPs
cidr_subnet           = "10.0.16.0/20"    # 4,096 IPs
cidr_secondary_subnet = "10.0.32.0/20"    # 4,096 IPs
```

## Features

- **Multi-AZ Support:** Secondary subnet in different AZ for RDS
- **Consistent Tagging:** All resources tagged with environment
- **Security by Default:** Private subnets for sensitive resources
- **Cost Optimized:** Single NAT gateway for demo environments
- **Flexible Configuration:** Optional components for different use cases

## Troubleshooting

### Network Connectivity Issues
```bash
# Test internet connectivity from private instances
# SSH into private instance via Teleport
tsh ssh ec2-user@private-instance

# Test outbound connectivity (should work via NAT)
curl -I https://google.com

# Test VPC internal connectivity
ping 10.0.0.10  # Another instance in VPC

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxx"
```

### Common Issues
- **No Internet Access from Private Subnet:** Check NAT gateway and route table associations
- **Inter-subnet Communication Failed:** Verify security group allows VPC CIDR traffic
- **RDS Connection Issues:** Ensure DB subnet group spans multiple AZs
- **Instance Launch Failed:** Check subnet has available IP addresses

### Debug Commands
```bash
# Check VPC configuration
aws ec2 describe-vpcs --vpc-ids vpc-xxxxx

# Verify subnet configuration
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx"

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test NAT gateway status
aws ec2 describe-nat-gateways
```

## Cost Considerations

- **NAT Gateway:** ~$45/month (largest cost component)
- **EIP for NAT:** ~$3.65/month when attached
- **VPC/Subnets/IGW:** Free
- **For cost optimization:** Consider using NAT instance instead of NAT gateway for demos