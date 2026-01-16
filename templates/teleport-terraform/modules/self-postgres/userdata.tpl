#!/bin/bash
set -euxo pipefail
# update hostname
hostnamectl set-hostname "${name}"
# packages
dnf update -y
dnf install -y postgresql15-server postgresql15 jq
# postgres install
postgresql-setup --initdb
systemctl enable postgresql
systemctl start postgresql
# Configure TLS directory
mkdir -p /var/lib/pgsql/data/certs
chmod 700 /var/lib/pgsql/data/certs
# add cert files for TLS
echo "${ca}"      > /var/lib/pgsql/data/certs/server.cas
echo "${tele_ca}" >> /var/lib/pgsql/data/certs/server.cas
echo "${cert}"    > /var/lib/pgsql/data/certs/server.crt
echo "${key}"     > /var/lib/pgsql/data/certs/server.key
chown -R postgres:postgres /var/lib/pgsql/data/certs/
chmod 600 /var/lib/pgsql/data/certs/*
# Update postgres config
cat >> /var/lib/pgsql/data/postgresql.conf <<EOF
ssl = on
ssl_cert_file = 'certs/server.crt'
ssl_key_file = 'certs/server.key'
ssl_ca_file = 'certs/server.cas'
EOF
# Replace pg_hba.conf with explicit rules for cert auth. File adjusted to put cert first otherwise it'll break
cat > /var/lib/pgsql/data/pg_hba.conf <<EOF
hostssl all             all             ::/0                    cert
hostssl all             all             0.0.0.0/0               cert
local   all             all                                     peer
host    all             all             127.0.0.1/32            ident
host    all             all             ::1/128                 ident
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            ident
host    replication     all             ::1/128                 ident
EOF
# bounce postgres to detect changes
systemctl restart postgresql
# Create users with CN-based cert auth
sudo -u postgres psql <<EOF
CREATE ROLE writer LOGIN;
GRANT ALL PRIVILEGES ON DATABASE postgres TO writer;
CREATE ROLE reader LOGIN;
GRANT CONNECT ON DATABASE postgres TO reader;
EOF
# install teleport
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise
# configure teleport
cat <<EOF > /etc/teleport.yaml
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
ssh_service:
  enabled: true
  labels:
    "tier": "${env}"
    "team": "${team}"
auth_service:
  enabled: false
proxy_service:
  enabled: false
EOF

systemctl enable teleport
systemctl restart teleport