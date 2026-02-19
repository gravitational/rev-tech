#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

hostnamectl set-hostname "${name}"

# Install dependencies
sudo dnf install -y docker jq
systemctl enable docker
systemctl start docker

# Create a dedicated user for running the MCP stdio command.
# The docker group is created by the package install; ensure the user exists in that group.
if ! id -u docker >/dev/null 2>&1; then
  useradd --system --shell /bin/false --gid docker docker
fi

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
  resources:
    - labels:
        env: "${env}"
        team: "${team}"
        teleport.dev/origin: "dynamic"
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
