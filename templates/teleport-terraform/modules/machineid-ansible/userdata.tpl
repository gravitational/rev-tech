#!/bin/bash
#cloud-config
set -euxo pipefail

hostnamectl set-hostname "${env}-ansible"

yum update -y
yum install -y jq python3 python3-pip git

# Install Ansible
pip3 install ansible

# Install Teleport
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise
echo "${node_token}" > /tmp/token

# Write teleport.yaml
cat <<-EOF > /etc/teleport.yaml
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  proxy_server: "${proxy_address}:443"
  auth_token: "/tmp/token"
  log:
    output: stderr
    severity: INFO
    format:
      output: text
ssh_service:
  enabled: true
  labels:
    tier: ${env}
    team: ${team}
  enhanced_recording:
    enabled: true
auth_service:
  enabled: false
proxy_service:
  enabled: false
db_service:
  enabled: false
EOF

systemctl enable teleport
systemctl start teleport

# Note: Not waiting for teleport since tbot is independent

# Configure Machine ID (tbot)
cat <<-EOF > /etc/tbot.yaml
version: v2
proxy_server: ${proxy_address}:443
onboarding:
  join_method: token
  token: ${bot_token}
storage:
  type: directory
  path: /var/lib/teleport/bot
outputs:
- type: identity
  destination:
    type: directory
    path: /opt/machine-id
EOF

# Create system user and directories with proper permissions
useradd --system --shell /bin/false teleport || true
mkdir -p /var/lib/teleport/bot
mkdir -p /opt/machine-id

# Set up proper group ownership for machine-id directory
chown -R teleport:teleport /var/lib/teleport/
chown -R teleport:teleport /opt/machine-id

# Add ec2-user to teleport group for access
usermod -aG teleport ec2-user

# Set group permissions on machine-id directory
chmod 2750 /opt/machine-id  # setgid bit ensures new files inherit group ownership
chmod -R g+rX /opt/machine-id  # Give group read and execute permissions

# Create tbot systemd service - independent of local teleport service
cat <<-EOF > /etc/systemd/system/tbot.service
[Unit]
Description=tbot - Teleport Machine ID Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=teleport
Group=teleport
Restart=always
RestartSec=15
StartLimitBurst=5
StartLimitIntervalSec=300
TimeoutStartSec=120
Environment="TELEPORT_ANONYMOUS_TELEMETRY=1"
UMask=0027
ExecStart=/usr/local/bin/tbot start -c /etc/tbot.yaml
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=524288

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable tbot
systemctl daemon-reload
systemctl enable tbot

# Start tbot - it will connect independently to the proxy server
echo "Starting tbot service..."
systemctl start tbot

# Wait for tbot to generate identity files (optional check)
echo "Checking if Machine ID identity is ready..."
for i in {1..30}; do
    if [ -f /opt/machine-id/identity ]; then
        echo "Machine ID identity is ready"
        # Fix permissions on generated files to be group-readable
        chmod -R g+r /opt/machine-id/
        break
    fi
    echo "Waiting for identity file... ($i/30)"
    sleep 2
done

if [ ! -f /opt/machine-id/identity ]; then
    echo "WARNING: Machine ID identity was not created yet. This may be normal - tbot will continue trying."
    echo "Check service status with: systemctl status tbot"
else
    echo "Fixed permissions on machine-id files for group access"
fi

# Configure Ansible
mkdir -p /home/ec2-user/ansible
cat <<EOF > /home/ec2-user/ansible/ansible.cfg
[defaults]
host_key_checking = False
inventory = ./hosts
remote_tmp = /tmp
stdout_callback = yaml

[ssh_connection]
scp_if_ssh = True
ssh_args = -F /opt/machine-id/ssh_config -o CanonicalizeHostname=yes -o CanonicalizeMaxDots=10 -o CanonicalDomains=${proxy_address}
EOF

cat <<-EOF > /home/ec2-user/ansible/playbook.yaml
---
- name: Check Teleport and SSHD status
  hosts: all
  remote_user: ec2-user
  become: true
  gather_facts: true
  tasks:
    - name: Check Teleport and SSHD service status
      ansible.builtin.systemd:
        name: "{{ item }}"
      register: service_status
      loop:
        - teleport
        - sshd
      failed_when: false

    - name: Get Teleport version if running
      command: teleport version
      register: teleport_version
      when: service_status.results[0].status.ActiveState == "active"
      changed_when: false
      failed_when: false

    - name: Stop SSHD if running
      ansible.builtin.systemd:
        name: sshd
        state: stopped
      when: service_status.results[1].status.ActiveState == "active"

    - name: Display results
      debug:
        msg:
          - "hostname: {{ ansible_facts['hostname'] }}"
          - "Teleport is {{ 'running' if service_status.results[0].status.ActiveState == 'active' else 'not running' }}"
          - "Teleport Version: {{ teleport_version.stdout_lines[0] if teleport_version.stdout is defined else 'N/A' }}"
          - "SSHD was {{ 'running and stopped' if service_status.results[1].status.ActiveState == 'active' else 'not running' }}"
EOF

chown -R ec2-user:ec2-user /home/ec2-user/ansible

# Create a helper script to fix machine-id permissions if needed
cat <<-'EOF' > /usr/local/bin/fix-machine-id-perms
#!/bin/bash
# Fix permissions on machine-id files for group access
chmod -R g+r /opt/machine-id/
echo "Fixed permissions on /opt/machine-id/ files"
EOF
chmod +x /usr/local/bin/fix-machine-id-perms

echo "Setup complete. Both services are independent:"
echo "Teleport SSH service status:"
systemctl status teleport --no-pager -l
echo "Machine ID (tbot) service status:"
systemctl status tbot --no-pager -l