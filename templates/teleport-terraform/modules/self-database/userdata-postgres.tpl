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
-- Schema-level grants. PostgreSQL 15 revoked CREATE on schema public from
-- PUBLIC, so the database-level GRANTs above are not enough on their own:
-- without these, writer connects fine but any CREATE TABLE fails with
-- "permission denied for schema public".
GRANT ALL ON SCHEMA public TO writer;
GRANT USAGE ON SCHEMA public TO reader;
-- Tables writer creates later are readable by reader without a manual grant.
ALTER DEFAULT PRIVILEGES FOR ROLE writer IN SCHEMA public GRANT SELECT ON TABLES TO reader;
%{ if seed_beams_demo ~}
-- beams cross-cluster quickstart. Mirrors that guide's appendix init.sql so the
-- guide runs verbatim against this host rather than its own Docker container.
-- The GRANT USAGE line is not in the upstream init.sql but is required on
-- PostgreSQL 15+, where beamuser otherwise cannot see the table it owns.
CREATE ROLE beamuser LOGIN;
GRANT USAGE ON SCHEMA public TO beamuser;
CREATE TABLE IF NOT EXISTS agent_actions (
  id         serial PRIMARY KEY,
  agent_id   text        NOT NULL,
  action     text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO agent_actions (agent_id, action) VALUES
  ('demo-agent-1', 'provisioned demo dataset'),
  ('demo-agent-1', 'read customer summary'),
  ('demo-agent-2', 'ran nightly reconciliation');
ALTER TABLE agent_actions OWNER TO beamuser;
GRANT ALL ON agent_actions TO beamuser;
GRANT USAGE, SELECT ON SEQUENCE agent_actions_id_seq TO beamuser;
%{ endif ~}
EOF
# install teleport
curl "https://${proxy_address}/scripts/install.sh" | bash
echo "${token}" > /tmp/token
# configure teleport
cat <<EOF > /etc/teleport.yaml
version: v3
teleport:
  data_dir: "/var/lib/teleport"
  proxy_server: "${proxy_address}:443"
  auth_token: /tmp/token
  log:
    output: stderr
    severity: INFO
    format:
      output: text
db_service:
  enabled: true
  resources:
    - labels:
        "env": "${env}"
        "team": "${team}"
ssh_service:
  enabled: "yes"
  labels:
    "env": "${env}"
    "team": "${team}"
auth_service:
  enabled: "no"
proxy_service:
  enabled: "no"
app_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl restart teleport
