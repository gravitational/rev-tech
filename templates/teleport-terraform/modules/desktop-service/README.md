# Linux Desktop Service Module

Creates a Linux instance running Teleport Desktop Service to provide secure access to Windows desktops through Teleport's Windows Desktop Access feature.

## Overview

- **Use Case:** Windows Desktop Access via Teleport Desktop Service
- **Teleport Features:** Desktop service, RDP proxy, session recording, Windows desktop discovery
- **Infrastructure:** Amazon Linux 2023 instance with Teleport Desktop Service configured

## Usage

```hcl
module "linux_desktop_service" {
  source = "../../modules/linux_desktop_service"
  
  env              = "dev"
  user             = "engineer@company.com"
  proxy_address    = "teleport.company.com"
  teleport_version = "17.5.2"
  
  ami_id               = data.aws_ami.linux.id
  instance_type        = "t3.small"
  subnet_id            = module.network.subnet_id
  security_group_ids   = [module.network.security_group_id]
  
  windows_internal_dns = module.windows_instance.private_dns
  windows_hosts = [
    {
      name    = module.windows_instance.hostname
      address = "${module.windows_instance.private_ip}:3389"
    }
  ]
}
```

## What It Creates

### AWS Resources
- **EC2 Instance:** Amazon Linux 2023 with Teleport Desktop Service
- **Network Configuration:** Configured to reach Windows instances on port 3389

### Teleport Resources
- **Provision Token:** For Desktop Service and SSH service registration
- **Static Desktop Hosts:** Windows desktops registered for access

### Teleport Services Enabled
- ** Desktop Service:** Windows desktop access and RDP proxy
- ** SSH Service:** Server management and troubleshooting access

## Label Structure & Access Control

This module applies consistent labels for RBAC and dynamic discovery:

```yaml
Labels Applied to Desktop Service:
  tier: "dev"          # From var.env - environment-based access
  team: "engineering"  # From var.team - team-based access

Labels Applied to SSH Service:
  tier: "dev"          # From var.env - environment-based access  
  team: "engineering"  # From var.team - team-based access

Labels Applied to Windows Desktops:
  tier: "dev"          # From var.env - environment-based access
  team: "engineering"  # From var.team - team-based access
```

### RBAC Integration
```yaml
# Example Teleport role using these labels:
allow:
  windows_desktop_labels:
    tier: ["dev", "staging"]     # Access dev and staging desktops
    team: ["engineering"]        # Only engineering team
  windows_desktop_logins: ["Administrator", "{{email.local(external.username)}}"]
  node_labels:
    tier: ["dev"]                # SSH access to desktop service
    team: ["engineering"]        # Same team restriction
```

### Customization
To adapt for your environment, modify the labels in your configuration:
```hcl
# Custom labels for your organization
labels = {
  tier        = "production"     # or "dev", "staging", "qa"
  team        = "platform"       # or "frontend", "backend", "data"
  region      = "us-west-2"      # Add region-specific access
  compliance  = "iso27001"       # Add compliance requirements
}
```

## Demo Commands

### Desktop Access
Access is available via the Teleport UI or [Teleport Connect](https://goteleport.com/docs/connect-your-client/teleport-connect/#installation--upgrade)


### SSH Access (Desktop Service Management)
```bash
# List SSH nodes (including desktop service)
tsh ls --labels=tier=dev

# SSH into the desktop service instance
tsh ssh ec2-user@dev-desktop-service

# Check Teleport desktop service status
sudo systemctl status teleport
sudo journalctl -u teleport -f

# Test connectivity to Windows instances
ping {windows-private-ip}
nc -zv {windows-private-ip} 3389
```

### Session Management
```bash
# View desktop session recordings
tsh recordings ls

# Play back desktop session
tsh play <session-id>
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment tag | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `windows_hosts` | List of Windows desktop hosts | `list(object)` | - |
| `ami_id` | AMI ID for instance | `string` | - |
| `instance_type` | EC2 instance type | `string` | `"t3.medium"` |
| `subnet_id` | Subnet for instance | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label | `string` | `"engineering"` |
| `windows_internal_dns` | Private DNS of Windows host | `string` | - |

## Outputs

| Output | Description |
|--------|-------------|
| `instance_id` | EC2 instance ID of desktop service |
| `private_ip` | Private IP address of desktop service |

## Windows Hosts Configuration

### Host Registration Format
```hcl
windows_hosts = [
  {
    name    = "dev-desktop-01"              # Name shown in tsh desktops ls
    address = "10.0.1.100:3389"             # Windows instance IP:port
  },
  {
    name    = "dev-desktop-02"
    address = "10.0.1.101:3389"
  }
]
```

### Static vs Dynamic Discovery
```yaml
# Current: Static host configuration
static_hosts:
  - name: dev-desktop
    addr: 10.0.1.100:3389
    labels:
      tier: dev
      team: engineering
```

## Desktop Service Configuration

### Key Teleport Settings
```yaml
windows_desktop_service:
  enabled: yes
  show_desktop_wallpaper: true              # Show wallpaper in sessions
  static_hosts:                             # Manually configured hosts
    - name: {hostname}
      ad: false                             # Not Active Directory joined
      addr: {windows_internal_dns}          # Windows instance address
      labels:
        tier: {env}
        team: {team}
```

### Network Requirements
- **Port 3389:** RDP access from Desktop Service to Windows instances
- **Port 443:** Desktop Service to Teleport Proxy
- **Security Groups:** Allow traffic between Desktop Service and Windows instances

## Integration Patterns

### Complete Desktop Access Setup
```hcl
# 1. Create Windows instance
module "windows_instance" {
  source = "../../modules/windows_instance"
  # ... configuration
}

# 2. Create Desktop Service pointing to Windows instance  
module "linux_desktop_service" {
  source               = "../../modules/linux_desktop_service"
  windows_internal_dns = module.windows_instance.private_dns
  windows_hosts = [
    {
      name    = module.windows_instance.hostname
      address = "${module.windows_instance.private_ip}:3389"
    }
  ]
  # ... other configuration
}
```

### Multiple Windows Instances
```hcl
module "linux_desktop_service" {
  source = "../../modules/linux_desktop_service"
  
  windows_hosts = [
    {
      name    = "dev-desktop-01"
      address = "${module.windows_instance_01.private_ip}:3389"
    },
    {
      name    = "dev-desktop-02" 
      address = "${module.windows_instance_02.private_ip}:3389"
    }
  ]
  # ... configuration
}
```

## Troubleshooting

### Multiple Services Status
This instance runs both desktop and SSH services:

```bash
# SSH into the desktop service first
tsh ssh ec2-user@dev-desktop-service

# Check all Teleport services
sudo systemctl status teleport
sudo journalctl -u teleport -f

# Check desktop service specifically
sudo cat /etc/teleport.yaml | grep -A 20 windows_desktop_service

# Test Windows connectivity
ping {windows-private-ip}
nc -zv {windows-private-ip} 3389
telnet {windows-private-ip} 3389
```

### Common Issues
- **Desktop Not Listed:** Check Windows instance is running and reachable
- **Connection Failed:** Verify network connectivity and security groups
- **SSH Access Denied:** Verify user roles and node labels
- **RDP Authentication Failed:** Check Windows user creation and certificate installation
- **Session Recording Failed:** Check disk space and Teleport configuration

### Service-Specific Debugging
```bash
# Test direct RDP connectivity (for debugging)
# From desktop service instance:
nc -zv {windows-private-ip} 3389

# SSH service issues
tsh ls --debug  
tctl nodes ls

# Check Windows desktop registration
tctl get windows_desktop/{hostname}
```

### Network Connectivity Debugging
```bash
# From desktop service instance, test Windows connectivity:
ping {windows-private-ip}
nc -zv {windows-private-ip} 3389

# Check security group rules
aws ec2 describe-security-groups --group-ids {sg-id}

# Test name resolution
nslookup {windows-internal-dns}
dig {windows-internal-dns}
```

### Windows Instance Debugging
```bash
# Verify Windows instance is ready
aws ec2 describe-instances --instance-ids {windows-instance-id}

# Check Windows instance system log
aws ec2 get-console-output --instance-id {windows-instance-id}

# Verify RDP is enabled on Windows (if you have direct access)
netstat -an | findstr :3389
```

## Features

- **RDP Proxy:** Secure RDP access through Teleport tunnel
- **Session Recording:** Complete desktop session audit trail
- **Certificate Authentication:** Integrates with Teleport's certificate auth
- **Multiple Desktops:** Can manage multiple Windows instances
- **Network Isolation:** Windows instances accessible only through Desktop Service
- **Dual Service Access:** Both desktop and SSH access for complete management

## Performance Considerations

- **Network Latency:** Desktop responsiveness depends on network latency
- **Bandwidth Usage:** RDP sessions consume ~50-500 Kbps depending on activity
- **Concurrent Sessions:** Desktop Service can handle multiple concurrent RDP sessions
- **Resource Usage:** Desktop Service itself is lightweight (~100MB RAM)

## Security Features

- **Network Isolation:** Windows instances in private subnets
- **Certificate Authentication:** Strong authentication via Teleport certificates  
- **Session Audit:** All desktop interactions recorded and auditable
- **Access Control:** Role-based access to specific desktop instances
- **Encrypted Transport:** All RDP traffic encrypted through Teleport tunnel

## Advanced Configuration

### Custom Desktop Labels
```yaml
# In teleport.yaml, customize desktop labels:
static_hosts:
  - name: production-desktop
    addr: 10.0.1.100:3389
    labels:
      tier: production
      team: platform
      compliance: pci
      region: us-west-2
```
