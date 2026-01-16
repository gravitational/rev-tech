#!/bin/bash
set -euxo pipefail

# Set hostname
hostnamectl set-hostname "${name}"

# Install dependencies
dnf update -y
dnf install -y mariadb105-server jq

systemctl enable mariadb
systemctl start mariadb

# Secure MySQL (non-interactive)
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

# Install Teleport
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

# Write teleport.yaml
cat > /etc/teleport.yaml <<EOF
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  proxy_server: "${proxy_address}:443"
  auth_token: "${token}"
  log:
    output: stderr
    severity: INFO
    format:
      output: text
db_service:
  enabled: true
  resources:
    - labels:
        "tier": "${env}"
        "team": "${team}"
auth_service:
  enabled: "no"
ssh_service:
  enabled: "yes"
  labels:
    "tier": "${env}"
    "team": "${team}"
proxy_service:
  enabled: "no"
app_service:
  enabled: "no"
EOF

# TLS setup for MySQL
mkdir -p /etc/mysql/ssl
echo "${ca}"      > /etc/mysql/ssl/server.cas
echo "${tele_ca}" >> /etc/mysql/ssl/server.cas
echo "${cert}"    > /etc/mysql/ssl/server.crt
echo "${key}"     > /etc/mysql/ssl/server.key

# Configure MariaDB for TLS
cat > /etc/my.cnf.d/ssl.cnf <<EOF
[mariadb]
require_secure_transport=ON
ssl-ca=/etc/mysql/ssl/server.cas
ssl-cert=/etc/mysql/ssl/server.crt
ssl-key=/etc/mysql/ssl/server.key
log_error=/var/log/mysqld.log
EOF

# Create users for Teleport certificate auth
mysql -e "CREATE USER 'writer'@'%' REQUIRE SUBJECT '/CN=writer';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'writer'@'%';"
mysql -e "CREATE USER 'reader'@'%' REQUIRE SUBJECT '/CN=reader';"
mysql -e "GRANT SELECT, SHOW VIEW ON *.* TO 'reader'@'%';"
mysql -e "FLUSH PRIVILEGES;"

# Restart services
systemctl restart mariadb
systemctl enable teleport
systemctl restart teleport