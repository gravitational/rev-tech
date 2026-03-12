#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "${name}"

# Install dependencies
sudo dnf install -y jq

# Install Teleport from cluster script
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

# Configure Teleport app+node services
cat <<EOF_TEL >/etc/teleport.yaml
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
  enabled: "yes"
  apps:
    - name: "${app_a_name}"
      uri: "${app_a_uri}"
      public_addr: "${app_a_public_addr}"
      cloud: "AWS"
      labels:
        aws_account_id: "${app_a_aws_account_id}"
        env: "${app_env}"
        team: "${app_a_team}"
%{ if enable_app_b ~}
    - name: "${app_b_name}"
      uri: "${app_b_uri}"
      public_addr: "${app_b_public_addr}"
      cloud: "AWS"
      labels:
        aws_account_id: "${app_b_aws_account_id}"
        env: "${app_env}"
        team: "${app_b_team}"
%{ if app_b_external_id != null ~}
      aws:
        external_id: "${app_b_external_id}"
%{ endif ~}
%{ endif ~}
ssh_service:
  enabled: "yes"
  labels:
    env: "${host_env}"
    team: "${host_team}"
auth_service:
  enabled: "no"
proxy_service:
  enabled: "no"
EOF_TEL

echo "${token}" >/tmp/token

systemctl enable teleport
systemctl restart teleport
