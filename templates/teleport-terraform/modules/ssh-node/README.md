# SSH Node Module

Creates EC2 instances with Teleport SSH service for demonstrating server access capabilities.

## Overview

- **Use Case:** SSH server access demonstration
- **Teleport Features:** SSH access, enhanced recording, dynamic labels, session recording
- **Infrastructure:** EC2 instances with Teleport agent configured

## Usage

```hcl
module "ssh_nodes" {
  source = "../../modules/ssh_node"
  
  env              = "dev"
  user             = "engineer@company.com"
  proxy_address    = "teleport.company.com"
  teleport_version = "18.4.1"
  
  agent_count        = 3 #adjust to get more or less agents depending on use case
  ami_id             = data.aws_ami.linux.id
  instance_type      = "t3.micro"
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## What It Creates

### AWS Resources
- **EC2 Instances:** Multiple Linux instances with Teleport SSH service
- **Security Groups:** Configured for Teleport agent communication

### Teleport Resources
- **Provision Token:** Short-lived token for agent registration
- **SSH Nodes:** Automatically registered with dynamic labels

### Teleport Services Enabled
- **SSH Service:** Server access with enhanced recording and monitoring

### OS Services Enabled 
- **Nginx:** Web/Proxy server for testing of service on machine

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
  node_labels:
    tier: ["dev", "staging"]     # Access dev and staging servers
    team: ["engineering"]        # Only engineering team
  logins: ["ec2-user", "ubuntu"]  # Allowed system users
```

### Customization
To adapt for your environment, modify the labels in your configuration:
```hcl
# Custom labels for your organization
labels = {
  tier        = "production"     # or "dev", "staging", "qa"
  team        = "platform"       # or "frontend", "backend", "data"
  region      = "us-west-2"      # Add region-specific access
  role        = "web-server"     # Add server role classification
  compliance  = "sox"            # Add compliance requirements
}
```

## Demo Commands

```bash
# List SSH nodes
tsh ls --labels=tier=dev

# SSH into a node
tsh ssh ec2-user@dev-ssh-0

# Start recorded session
tsh ssh ec2-user@dev-ssh-1

# View session recordings
tsh recordings ls
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment name | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `agent_count` | Number of SSH nodes to create | `number` | - |
| `ami_id` | AMI ID for instances | `string` | - |
| `instance_type` | EC2 instance type | `string` | - |
| `subnet_id` | Subnet for instances | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label for nodes | `string` | `"engineering"` |

## Outputs

| Output | Description |
|--------|-------------|
| `provision_token` | Token used for agent registration |
| `private_ips` | Private IP addresses of created instances |

## Features

- **Enhanced Recording:** Command and network recording enabled
- **Dynamic Labels:** Automatic labeling with tier and team
- **Custom Commands:** Hostname, load average, and disk usage monitoring
- **Multiple Instances:** Configurable number of nodes for load testing

## Troubleshooting

### Service Status
This instance runs only SSH service for focused server access demos:

```bash
# Check all deployed nodes
tsh ls --labels=tier=dev

# SSH into specific nodes
tsh ssh ec2-user@dev-ssh-0
tsh ssh ec2-user@dev-ssh-1

# On the server, check Teleport status
sudo systemctl status teleport
sudo journalctl -u teleport -f

# View Teleport configuration
sudo cat /etc/teleport.yaml
```

### Common Issues
- **Node Not Listed:** Check agent registration and token validity
- **SSH Access Denied:** Verify user roles and node labels  
- **Enhanced Recording Failed:** Check disk space and permissions
- **Custom Commands Not Running:** Verify command execution permissions

### Debug Commands
```bash
# Check node registration
tctl nodes ls
tsh ls --debug

# Test specific node access
tsh ssh ec2-user@dev-ssh-0 --debug

# View session recordings
tsh recordings ls
tsh play <session-id>

# Check custom command output
tsh ssh ec2-user@dev-ssh-0 "hostname && uptime"
```