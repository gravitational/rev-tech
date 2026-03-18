#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "teleport-ec2-discovery-${env}"

# NAT gateway routes may take a moment to propagate after instance boot.
until curl -sf --connect-timeout 5 "https://${proxy_address}/webapi/ping" >/dev/null 2>&1; do
  echo "Waiting for network connectivity..."
  sleep 10
done

curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

echo "${token}" > /tmp/token

cat <<EOF >/etc/teleport.yaml
version: v3
teleport:
  auth_token: /tmp/token
  proxy_server: ${proxy_address}:443
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO
    format:
      output: text

ssh_service:
  enabled: "yes"
  labels:
    env: ${env}
    team: ${team}
    role: ec2-discovery-agent

discovery_service:
  enabled: true
  # discovery_group identifies this agent's set of discovered resources in Teleport.
  discovery_group: "${discovery_group}"
  aws:
    - types: ["ec2"]
      regions: ["${region}"]
      ssm:
        document_name: "TeleportDiscoveryInstaller"
      install:
        join_params:
          token_name: "${join_token_name}"
          method: "iam"
      tags:
        "${ec2_tag_key}": "${ec2_tag_value}"

proxy_service:
  enabled: "no"
auth_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl start teleport
