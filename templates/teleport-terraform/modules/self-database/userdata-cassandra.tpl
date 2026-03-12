#!/bin/bash
set -euxo pipefail

# Set hostname
hostnamectl set-hostname "${name}"

# Install Java 11 (Cassandra 4.1 default JVM opts use CMS GC, removed in Java 17)
dnf update -y
dnf install -y java-11-amazon-corretto jq nmap-ncat

# Add Apache Cassandra 4.1 repository
cat > /etc/yum.repos.d/cassandra.repo <<EOF
[cassandra]
name=Apache Cassandra
baseurl=https://redhat.cassandra.apache.org/41x/
gpgcheck=1
gpgkey=https://downloads.apache.org/cassandra/KEYS
enabled=1
EOF

# Install Cassandra
dnf install -y cassandra

# Create TLS cert directory
mkdir -p /etc/cassandra/certs
chmod 755 /etc/cassandra/certs

# Write PEM files
echo "${ca}"      > /etc/cassandra/certs/ca.crt
echo "${tele_ca}" > /etc/cassandra/certs/tele-ca.crt
echo "${cert}"    > /etc/cassandra/certs/server.crt
echo "${key}"     > /etc/cassandra/certs/server.key

# Create PKCS12 keystore from PEM cert+key.
# Java 11 reads PKCS12 natively; no -legacy flag needed.
openssl pkcs12 -export \
  -in /etc/cassandra/certs/server.crt \
  -inkey /etc/cassandra/certs/server.key \
  -out /etc/cassandra/certs/server.keystore.p12 \
  -name cassandra \
  -passout pass:cassandra

# Create PKCS12 truststore with both CAs:
#   db-ca       — verifies Cassandra's own server cert (self-signed CA from Terraform)
#   teleport-ca — verifies client certs presented by Teleport's DB service (mTLS)
keytool -import -noprompt -alias db-ca \
  -file /etc/cassandra/certs/ca.crt \
  -keystore /etc/cassandra/certs/server.truststore.p12 \
  -storetype PKCS12 \
  -storepass cassandra

keytool -import -noprompt -alias teleport-ca \
  -file /etc/cassandra/certs/tele-ca.crt \
  -keystore /etc/cassandra/certs/server.truststore.p12 \
  -storetype PKCS12 \
  -storepass cassandra

# Set permissions — Cassandra runs as cassandra user
chown -R cassandra:cassandra /etc/cassandra/certs
chmod 640 /etc/cassandra/certs/server.keystore.p12
chmod 644 /etc/cassandra/certs/server.truststore.p12

###############################################################################
# Configure cassandra.yaml.
#
# Teleport's Cassandra engine authenticates via mTLS (client cert signed by the
# Teleport DB CA) — it does NOT support PasswordAuthenticator's SASL exchange.
# AllowAllAuthenticator lets any mTLS-authenticated connection through; Teleport
# enforces access control at the proxy level.
#
# Use regex replacement to preserve Cassandra's YAML formatting exactly —
# yaml.safe_load + yaml.dump reformats the file in ways Cassandra rejects.
###############################################################################
python3 - <<'PYEOF'
import re

with open('/etc/cassandra/conf/cassandra.yaml', 'r') as f:
    content = f.read()

# AllowAllAuthenticator: mTLS is the security boundary; Cassandra trusts the cert.
content = re.sub(r'^authenticator:.*', 'authenticator: AllowAllAuthenticator', content, flags=re.MULTILINE)
content = re.sub(r'^authorizer:.*',    'authorizer: AllowAllAuthorizer',        content, flags=re.MULTILINE)

# Enable mTLS: Cassandra presents its server cert; Teleport DB service presents
# a client cert signed by the Teleport DB CA (imported into server.truststore.p12).
new_tls_block = (
    "client_encryption_options:\n"
    "    enabled: true\n"
    "    optional: false\n"
    "    keystore: /etc/cassandra/certs/server.keystore.p12\n"
    "    keystore_password: cassandra\n"
    "    require_client_auth: true\n"
    "    truststore: /etc/cassandra/certs/server.truststore.p12\n"
    "    truststore_password: cassandra\n"
    "    store_type: PKCS12\n"
)
content, n = re.subn(
    r'^client_encryption_options:.*?(?=^\w|\Z)',
    new_tls_block,
    content,
    flags=re.MULTILINE | re.DOTALL,
)
if n == 0:
    raise RuntimeError("client_encryption_options block not found in cassandra.yaml")

with open('/etc/cassandra/conf/cassandra.yaml', 'w') as f:
    f.write(content)
PYEOF

# Install Teleport before starting Cassandra so SSH is available for debugging
# if Cassandra fails to start.
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise
echo "${token}" > /tmp/token

cat > /etc/teleport.yaml <<EOF
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
auth_service:
  enabled: "no"
ssh_service:
  enabled: "yes"
  labels:
    "env": "${env}"
    "team": "${team}"
proxy_service:
  enabled: "no"
app_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl start teleport

# Start Cassandra
systemctl enable cassandra
systemctl start cassandra

# Wait for port 9042 to open
sleep 30
until nc -z 127.0.0.1 9042 2>/dev/null; do
  echo "Waiting for Cassandra port 9042..."
  sleep 5
done
