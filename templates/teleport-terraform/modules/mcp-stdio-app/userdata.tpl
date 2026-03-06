#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

hostnamectl set-hostname "${name}"

# Install dependencies
# docker was removed from the standard AL2023 repos; install Docker CE from the
# CentOS repo with $releasever pinned to 9 (AL2023 is glibc-compatible with
# CentOS Stream 9; AL2023's own $releasever resolves to "2023" which has no
# matching path in Docker's repo).
dnf install -y jq
curl -o /etc/yum.repos.d/docker-ce.repo \
  https://download.docker.com/linux/centos/docker-ce.repo
sed -i 's/\$releasever/9/g' /etc/yum.repos.d/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io --allowerasing
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
