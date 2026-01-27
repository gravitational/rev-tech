#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "${name}"

# Install dependencies
sudo dnf install -y docker jq
systemctl enable docker
systemctl start docker

# Create a dedicated user for running the MCP stdio command
useradd --system --shell /bin/false docker || true
usermod -aG docker docker

# Install Teleport
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

# Write token to disk
echo "${token}" > /tmp/token

# Configure Teleport Application Service with MCP stdio server
cat <<EOF_TEL > /etc/teleport.yaml
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  auth_token: "/tmp/token"
  proxy_server: ${proxy_address}:443
  log:
    output: stderr
    severity: INFO
    format:
      output: text
app_service:
  enabled: true
  apps:
    - name: "${app_name}"
      description: "${app_description}"
      labels:
        env: "${env}"
        team: "${team}"
      mcp:
        command: "${mcp_command}"
        args: ${mcp_args_json}
        run_as_host_user: "${run_as_host_user}"
ssh_service:
  enabled: true
  labels:
    env: "${env}"
    team: "${team}"
auth_service:
  enabled: false
proxy_service:
  enabled: false
EOF_TEL

systemctl enable teleport
systemctl restart teleport
