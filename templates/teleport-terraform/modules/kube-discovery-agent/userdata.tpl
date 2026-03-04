#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "teleport-kube-discovery-${env}"

curl "https://${proxy_address}/scripts/install.sh" | bash

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

kubernetes_service:
  enabled: true
  # Pick up all clusters registered in Teleport (including auto-discovered ones).
  resources:
    - labels:
        "*": "*"

discovery_service:
  enabled: true
  # discovery_group links the discovery service to this kubernetes_service.
  # All EKS clusters found in this group are proxied by this agent.
  discovery_group: "${discovery_group}"
  aws:
    - types: ["eks"]
      regions: ["${region}"]
      tags:
        "${eks_tag_key}": "${eks_tag_value}"

proxy_service:
  enabled: false
auth_service:
  enabled: false
EOF

systemctl enable teleport
systemctl start teleport
