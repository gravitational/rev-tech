#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname "${name}"

# Install auditd — Teleport SSH service automatically writes session events to the
# Linux Audit System when it detects auditd running. No Teleport config needed.
dnf install -y audit nginx
systemctl enable --now auditd

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
    # BPF/eBPF enhanced session recording — captures commands, arguments, and
    # network connections. Requires kernel 5.8+ (AL2023 ships 6.x).
    enabled: true
    command_buffer_size: 8
    disk_buffer_size: 128
    network_buffer_size: 8
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
      # NR==2 selects the data row; the old egrep '^[0-9][0-9]' filter exited 1
      # (label shows "exit status 1") whenever disk usage dropped to single digits
      command: ["/bin/sh", "-c", "df -hTP / | awk 'NR==2 {print \$6}'"]
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
