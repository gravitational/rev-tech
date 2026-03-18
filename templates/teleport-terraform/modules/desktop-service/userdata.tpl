#!/bin/bash
set -euxo pipefail

# set hostname
hostnamectl set-hostname "${name}"

# Teleport does not allow periods in windows names
WINDOWS_HOST_NAME=$(echo "${windows_internal_dns}" | awk -F. '{print $1}')

# Install Teleport
echo "${token}" > /tmp/token

# installs teleport enterprise edition
# update for versions >17.3
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

# Log installed version for debugging
teleport --version || true

sudo cat << EOF > /etc/teleport.yaml
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  auth_token: /tmp/token
  proxy_server: ${proxy_address}:443
  log:
    output: stderr
    severity: INFO
    format:
      output: json
app_service:
  enabled: "no"
auth_service:
  enabled: "no"
db_service:
  enabled: "no"
discovery_service:
  enabled: "yes"
kubernetes_service:
  enabled: "no"
proxy_service:
  enabled: "no"
ssh_service:
  enabled: "yes"
  commands:
  - name: hostname
    command: [hostname]
    period: 1m0s
  labels:
    "env": "${env}"
    "team": "${team}"
  enhanced_recording:
    enabled: "false"
windows_desktop_service:
  enabled: "yes"
  show_desktop_wallpaper: true
  static_hosts:
  - name: $WINDOWS_HOST_NAME
    ad: false
    addr: ${windows_internal_dns}
    labels:
      "env": "${env}"
      "team": "${team}"
EOF

# Sets teleport service to start at boot and brings it up
systemctl enable teleport
systemctl restart teleport

# Log setup complete
echo "[INFO] Teleport windows_desktop_service setup complete."
