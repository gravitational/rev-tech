#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "teleport-kube-discovery-${env}"

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
    role: kube-discovery-agent

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
      regions: ${jsonencode(discovery_regions)}
      tags:
        "${eks_tag_key}": "${eks_tag_value}"

proxy_service:
  enabled: "no"
auth_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl start teleport

# Write Teleport startup diagnostics to the serial console after 60s.
# View with: aws ec2 get-console-output --instance-id <id> --region <region> --output text
{
  sleep 60
  echo "=== teleport.yaml ===" >/dev/console
  cat /etc/teleport.yaml >/dev/console 2>&1
  echo "=== Teleport Status ===" >/dev/console
  systemctl status teleport --no-pager >/dev/console 2>&1
  echo "=== Teleport Logs ===" >/dev/console
  journalctl -u teleport -n 80 --no-pager >/dev/console 2>&1
} &
