# Machine ID Ansible Module

Creates an Amazon Linux instance with Teleport Machine ID (tbot) and Ansible configured for automated infrastructure management and demonstrating machine-to-machine authentication.

## Overview

- **Use Case:** Automated infrastructure management with Machine ID authentication
- **Teleport Features:** Machine ID (tbot), certificate-based automation, SSH access via bot identity
- **Infrastructure:** EC2 instance with Ansible, tbot service, and Teleport SSH agent

## Usage

```hcl
module "machineid_ansible" {
  source = "../../modules/machineid_ansible"
  
  env              = "dev"
  user             = "engineer@company.com"
  proxy_address    = "teleport.company.com"
  teleport_version = "17.5.2"
  
  subnet_id          = module.network.subnet_id
  security_group_ids = [module.network.security_group_id]
}
```

## What It Creates

### AWS Resources
- **EC2 Instance:** Amazon Linux 2023 with Ansible and Python 3
- **IAM Configuration:** No special IAM roles (uses Teleport for authentication)

### Teleport Resources
- **Bot Identity:** `ansible` bot with appropriate roles for infrastructure access
- **Bot Token:** Provision token for bot authentication
- **Teleport Role:** Custom role for machine access to target nodes

### Teleport Services Enabled
- ** Machine ID (tbot):** Automated certificate renewal and identity management
- ** SSH Service:** Server management and troubleshooting access

## Label Structure & Access Control

This module applies consistent labels for RBAC and dynamic discovery:

```yaml
Labels Applied to SSH Service:
  tier: "dev"          # From var.env - environment-based access
  team: "engineering"  # From var.team - team-based access

Bot Role Permissions (target nodes):
  node_labels:
    tier: ["dev"]        # Bot can access dev nodes
    team: ["engineering"] # Within engineering team
```

### RBAC Integration
```yaml
# Bot role created by this module:
ansible-machine-role:
  allow:
    logins: ["ec2-user", "{user}"]      # System users bot can access
    node_labels:
      tier: ["dev"]                     # Environment restriction
      team: ["engineering"]             # Team restriction

# Example human role that can manage the bot instance:
allow:
  node_labels:
    tier: ["dev"]
    team: ["engineering"]
```

### Customization
To adapt for your environment, modify the bot permissions:
```hcl
# Custom role configuration for bot access
allowed_logins = ["ubuntu", "ec2-user", "admin"]
node_labels = {
  tier        = ["production", "staging"]  # Multi-environment access
  team        = ["platform", "sre"]        # Multi-team access
  environment = ["us-west-2"]              # Region-specific access
}
```

## Demo Commands

### Machine ID Operations
```bash
# SSH into the Ansible instance
tsh ssh ec2-user@dev-ansible

# Check tbot status
sudo systemctl status tbot
sudo journalctl -u tbot -f

# Verify identity files are generated
ls -la /opt/machine-id/
cat /opt/machine-id/ssh_config

# Test bot authentication
ssh -F /opt/machine-id/ssh_config {target-hostname}
```

### Ansible Automation
```bash
# SSH into the Ansible instance
tsh ssh ec2-user@dev-ansible
cd /home/ec2-user/ansible

# List target hosts via Teleport
ssh -F /opt/machine-id/ssh_config {target-hostname}.{proxy_address}

# Run Ansible playbook using Teleport authentication
ansible-playbook playbook.yaml

# Check ansible configuration
cat ansible.cfg
cat playbook.yaml
```

### SSH Access (Server Management)
```bash
# List SSH nodes (including Ansible instance)
tsh ls --labels=tier=dev

# SSH into the Ansible management server
tsh ssh ec2-user@dev-ansible

# Check system status
sudo systemctl status teleport
sudo systemctl status tbot
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `env` | Environment tag | `string` | - |
| `user` | Creator tag | `string` | - |
| `proxy_address` | Teleport proxy address | `string` | - |
| `teleport_version` | Teleport version to install | `string` | - |
| `subnet_id` | Subnet for instance | `string` | - |
| `security_group_ids` | Security group IDs | `list(string)` | - |
| `team` | Team label | `string` | `"engineering"` |

## Outputs

*No outputs defined - this module focuses on automation setup*

## Machine ID Configuration

### Bot Configuration (`/etc/tbot.yaml`)
```yaml
version: v2
proxy_server: {proxy_address}:443
onboarding:
  join_method: token
  token: {bot_token}
storage:
  type: directory
  path: /var/lib/teleport/bot
outputs:
  - type: identity
    destination:
      type: directory
      path: /opt/machine-id
```

### Bot Identity Output
```bash
# Generated files in /opt/machine-id/:
identity              # Bot certificate identity
ssh_config           # SSH client configuration  
known_hosts          # Trusted host keys
ca.pem              # Teleport CA certificate
```

## Ansible Configuration

### Ansible Config (`/home/ec2-user/ansible/ansible.cfg`)
```ini
[defaults]
host_key_checking = False
inventory = ./hosts
remote_tmp = /tmp
stdout_callback = yaml

[ssh_connection]
scp_if_ssh = True
ssh_args = -F /opt/machine-id/ssh_config -o CanonicalizeHostname=yes -o CanonicalizeMaxDots=10 -o CanonicalDomains={proxy_address}
```

### Example Playbook (`/home/ec2-user/ansible/playbook.yaml`)
```yaml
---
- name: Check Teleport and SSHD status
  hosts: all
  remote_user: ec2-user
  become: true
  gather_facts: true
  tasks:
    - name: Check service status
      systemd:
        name: "{{ item }}"
      register: service_status
      loop: [teleport, sshd]
      
    - name: Stop SSHD if running
      systemd:
        name: sshd
        state: stopped
      when: service_status.results[1].status.ActiveState == "active"
```

## Integration

This module uses the `machineid_host` module internally for bot creation:

```hcl
# Internal module usage:
module "host_identity" {
  source = "../machineid_host"
  
  bot_name         = "ansible"
  role_name        = "ansible-machine-role"
  allowed_logins   = ["ec2-user", local.user]
  node_labels = {
    tier = [var.env]
    team = [var.team]
  }
}
```

## Use Cases

### Infrastructure Automation
```bash
# Use Ansible to manage infrastructure via Machine ID
cd /home/ec2-user/ansible

# Create inventory targeting Teleport nodes
echo "[teleport_nodes]" > hosts
tsh ls --format=names | grep dev >> hosts

# Run automation tasks
ansible all -m ping
ansible all -m setup
ansible-playbook system-updates.yaml
```

### CI/CD Integration
```bash
# Machine ID can be used in CI/CD pipelines
# Bot certificates provide secure, auditable access
# No need for SSH keys or shared credentials

# Example CI/CD workflow:
1. CI system gets bot token
2. tbot generates certificates  
3. Ansible uses certificates for deployment
4. All actions audited in Teleport
```

### Security Compliance
```bash
# All automation activities are audited
tsh recordings ls --type=ssh
tctl get sessions

# Bot identity rotates automatically
# No long-lived credentials to manage
```

## Troubleshooting

### Multiple Services Status
This instance runs both Machine ID and SSH services:

```bash
# SSH into the Ansible instance
tsh ssh ec2-user@dev-ansible

# Check all services
sudo systemctl status teleport
sudo systemctl status tbot

# Check service logs
sudo journalctl -u teleport -f
sudo journalctl -u tbot -f

# Verify bot identity generation
ls -la /opt/machine-id/
cat /opt/machine-id/ssh_config
```

### Common Issues
- **Bot Registration Failed:** Check bot token validity and network connectivity
- **Identity Not Generated:** Verify tbot service is running and has proper permissions
- **SSH Authentication Failed:** Check bot role permissions and target node labels
- **Ansible Connection Failed:** Verify SSH configuration and bot certificates
- **Permission Denied:** Check bot role allows access to target nodes

### Service-Specific Debugging
```bash
# Machine ID (tbot) issues
sudo journalctl -u tbot -f
ls -la /var/lib/teleport/bot/
ls -la /opt/machine-id/

# SSH service issues
tsh ls --debug
tctl nodes ls

# Bot authentication testing
ssh -F /opt/machine-id/ssh_config -v {target-hostname}.{proxy_address}

# Ansible debugging
cd /home/ec2-user/ansible
ansible all -m ping -vvv
```

### Bot Identity Verification
```bash
# Check bot registration
tctl get bot/ansible
tctl get role/ansible-machine-role

# Verify bot token
tctl tokens ls

# Test bot certificate
openssl x509 -in /opt/machine-id/identity -text -noout

# Check SSH configuration
ssh -F /opt/machine-id/ssh_config -T {proxy_address}
```

## Features

- **Certificate Rotation:** Automatic bot certificate renewal
- **Audit Trail:** All automation activities logged and auditable
- **No Shared Secrets:** Uses certificates instead of SSH keys
- **Role-based Access:** Bot limited to specific nodes and users
- **Ansible Integration:** Pre-configured for immediate automation use
- **Service Management:** Both bot and regular SSH access for management

## Security Benefits

- **No SSH Keys:** Eliminates shared SSH key management
- **Certificate-based:** Uses short-lived certificates (renewed hourly)
- **Auditable:** All bot actions logged in Teleport audit log
- **Role-based:** Bot access limited by Teleport roles
- **Automatic Rotation:** No manual credential rotation required

## Performance Considerations

- **Certificate Renewal:** Occurs automatically every hour
- **Network Overhead:** Minimal overhead for certificate-based auth
- **Concurrent Connections:** Bot can handle multiple simultaneous Ansible operations
- **Resource Usage:** Lightweight - tbot uses minimal system resources

## Advanced Configuration

### Custom Bot Roles
```yaml
# Create specialized roles for different automation tasks
deployment-bot:
  allow:
    logins: ["deploy", "app"]
    node_labels:
      environment: ["production"]
      service: ["web", "api"]
      
monitoring-bot:  
  allow:
    logins: ["monitoring"]
    node_labels:
      tier: ["*"]
      team: ["sre"]
```

### Multi-Environment Access
```hcl
# Bot with access to multiple environments
node_labels = {
  tier = ["dev", "staging", "prod"]
  team = ["platform"]
  region = ["us-west-2", "us-east-1"]
}
```

### Custom Ansible Configurations
```bash
# Add custom Ansible roles and playbooks
cd /home/ec2-user/ansible
mkdir -p roles/teleport
mkdir -p group_vars
mkdir -p host_vars

# Create environment-specific configurations
echo "ansible_ssh_common_args: '-F /opt/machine-id/ssh_config'" > group_vars/all.yml
```