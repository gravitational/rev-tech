#!/bin/bash
set -euxo pipefail
hostnamectl set-hostname "${name}"
dnf install nginx -y 
curl "https://${proxy_address}/scripts/install.sh" | bash
echo "${token}" > /tmp/token

cat<<EOF >/etc/teleport.yaml
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
  enabled: true
  enhanced_recording:
    # Enable or disable enhanced auditing for this node. Default value: false.
    enabled: true
  labels:
    env: ${env}
    team: ${team}
  commands:
    - name: "hostname"
      command: ["/bin/hostname"]
      period: "1m0s"
    - name: "load_average"
      command: ["/bin/sh", "-c", "cut -d' ' -f1 /proc/loadavg"]
      period: "30s"
    - name: "disk_used"
      command: ["/bin/sh", "-c", "df -hTP / | awk '{print \$6}' | egrep '^[0-9][0-9]'"]
      period: "2m0s"
proxy_service:
  enabled: false
auth_service:
  enabled: false
EOF

systemctl enable teleport
systemctl start teleport
systemctl enable nginx
systemctl restart nginx