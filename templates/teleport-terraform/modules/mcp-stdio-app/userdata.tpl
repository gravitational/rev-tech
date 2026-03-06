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

# Create demo files for mcp/filesystem — gives Claude something to explore in the demo.
mkdir -p /demo-files/config /demo-files/logs
chown -R docker:docker /demo-files

cat > /demo-files/README.md << 'DEMO_EOF'
# Analytics API — Internal Service

Collects and aggregates telemetry from production workloads and exposes a
REST API for the data team's dashboards.

Owner: platform-team
Environment: see DEMO_ENV label on this host
DEMO_EOF

cat > /demo-files/config/app.yaml << 'DEMO_EOF'
service:
  name: analytics-api
  port: 8080
  workers: 4
  log_level: info
  debug: false

auth:
  provider: teleport
  audience: analytics-api
  require_mfa: true

cors:
  allowed_origins:
    - "https://dashboard.internal.example.com"
  allow_credentials: true

rate_limiting:
  enabled: true
  requests_per_minute: 1000
DEMO_EOF

cat > /demo-files/config/database.yaml << 'DEMO_EOF'
primary:
  host: db-primary.internal.example.com
  port: 5432
  database: analytics
  user: analytics_svc
  ssl_mode: verify-full
  # Credentials managed by Vault — not stored here

replica:
  host: db-replica.internal.example.com
  port: 5432
  database: analytics
  user: analytics_ro
  ssl_mode: verify-full

pool:
  min_connections: 2
  max_connections: 10
  idle_timeout_seconds: 300
DEMO_EOF

cat > /demo-files/logs/recent.log << 'DEMO_EOF'
2026-03-06T07:45:01Z INFO  GET /api/v1/metrics 200 alice@example.com 38ms
2026-03-06T07:46:12Z INFO  GET /api/v1/metrics 200 bob@example.com 45ms
2026-03-06T07:47:33Z WARN  GET /api/v1/admin/export 403 charlie@example.com 11ms
2026-03-06T07:48:02Z INFO  POST /api/v1/events 201 alice@example.com 142ms
2026-03-06T07:49:17Z ERROR GET /api/v1/metrics 500 bob@example.com 1823ms
2026-03-06T07:50:44Z WARN  GET /api/v1/admin/export 403 unknown 9ms
2026-03-06T07:51:30Z INFO  GET /api/v1/metrics 200 alice@example.com 41ms
2026-03-06T07:52:05Z INFO  GET /api/v1/health 200 healthcheck 3ms
DEMO_EOF
