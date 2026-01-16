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
  enabled: false
auth_service:
  enabled: false
db_service:
  enabled: false
discovery_service:
  enabled: true
kubernetes_service:
  enabled: false
proxy_service:
  enabled: false
ssh_service:
  enabled: true
  commands:
  - name: hostname
    command: [hostname]
    period: 1m0s
  labels:
    "tier": "${env}"
    "team": "${team}"
  enhanced_recording:
    enabled: "false"
windows_desktop_service:
  enabled: yes
  show_desktop_wallpaper: true
  static_hosts:
  - name: $WINDOWS_HOST_NAME
    ad: false
    addr: ${windows_internal_dns}
    labels:
      "tier": "${env}"
      "team": "${team}"
EOF

# Sets teleport service to start at boot and brings it up
systemctl enable teleport;
systemctl restart teleport;

# Log setup complete
echo "[INFO] Teleport windows_desktop_service setup complete."
