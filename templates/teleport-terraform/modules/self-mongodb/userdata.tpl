#!/bin/bash
set -euxo pipefail

# Set hostname
hostnamectl set-hostname "${name}"

# Install dependencies
dnf update -y
dnf install -y jq

# Create MongoDB repository file (MongoDB 7.0 is stable for Amazon Linux 2023)
cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<EOF
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF

# Install MongoDB
dnf install -y mongodb-org

# TLS setup for MongoDB
mkdir -p /etc/certs
echo "${ca}"      > /etc/certs/mongo.cas
echo "${tele_ca}" >> /etc/certs/mongo.cas

# Combine certificate and key into single file as required by MongoDB TLS config
cat > /etc/certs/mongo.crt <<EOF
${cert}
${key}
EOF

# Set proper permissions
chown -R mongod:mongod /etc/certs
chmod 400 /etc/certs/mongo.crt
chmod 444 /etc/certs/mongo.cas

# Configure MongoDB first WITHOUT TLS for initial systemd start
cat > /etc/mongod.conf <<EOF
# mongod.conf - Initial configuration without TLS

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# Where and how to store data.
storage:
  dbPath: /var/lib/mongo

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1

# security
security:
  authorization: enabled
EOF

# Start MongoDB via systemd first without TLS to initialize storage engine properly
systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to fully start and create metadata
sleep 20

# Verify MongoDB is running and accessible
mongosh --eval 'db.runCommand({hello: 1})' || echo "MongoDB not ready yet, waiting longer..."
sleep 10

# Now gracefully stop MongoDB to prepare for TLS configuration
systemctl stop mongod
sleep 10

# Update configuration to include TLS
cat > /etc/mongod.conf <<EOF
# mongod.conf - Final configuration with TLS

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# Where and how to store data.
storage:
  dbPath: /var/lib/mongo

# how the process runs
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# network interfaces
net:
  port: 27017
  bindIp: 0.0.0.0
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/certs/mongo.crt
    CAFile: /etc/certs/mongo.cas
    allowConnectionsWithoutCertificates: false

# security
security:
  authorization: enabled
EOF

# Ensure proper permissions and clean state
# Stop any running MongoDB processes first
systemctl stop mongod || true
pkill -f mongod || true
sleep 5

# Clean up any existing data and logs
rm -rf /var/lib/mongo/*
rm -rf /var/log/mongodb/*

# Set proper ownership and permissions
chown -R mongod:mongod /var/lib/mongo
chown -R mongod:mongod /var/log/mongodb
chmod 755 /var/lib/mongo
chmod 755 /var/log/mongodb

# Disable systemd service during initialization to avoid conflicts
systemctl disable mongod
systemctl stop mongod || true

# Create a simple initial configuration without TLS for user setup
cat > /etc/mongod-init.conf <<EOF
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod-init.log
storage:
  dbPath: /var/lib/mongo
net:
  port: 27017
  bindIp: 127.0.0.1
EOF

# Start MongoDB manually without systemd for initialization
mongod --config /etc/mongod-init.conf --fork

# Wait for MongoDB to be ready
sleep 15

# Create admin user
mongosh --eval '
db = db.getSiblingDB("admin");
db.createUser({
  user: "admin",
  pwd: "admin123", 
  roles: ["root"]
});
'

# Create Teleport users for X.509 certificate authentication in $external database
mongosh --eval '
db = db.getSiblingDB("admin");
db.auth("admin", "admin123");

// Create writer user for Teleport certificate auth
db.getSiblingDB("$external").runCommand({
  createUser: "CN=writer",
  roles: [
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" }
  ]
});

// Create reader user for Teleport certificate auth  
db.getSiblingDB("$external").runCommand({
  createUser: "CN=reader",
  roles: [
    { role: "readAnyDatabase", db: "admin" }
  ]
});
'

# Gracefully shutdown the temporary MongoDB instance
mongosh --eval 'db.getSiblingDB("admin").auth("admin", "admin123"); db.getSiblingDB("admin").shutdownServer();' || true
sleep 10

# Ensure all mongod processes are stopped
pkill -f mongod || true
sleep 5

# Fix ownership of all MongoDB files to mongod user
chown -R mongod:mongod /var/lib/mongo
chown -R mongod:mongod /var/log/mongodb

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

# Start services with proper TLS configuration
# Now that users are created, enable and start MongoDB with TLS via systemd
systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to start with TLS
sleep 15

# Enable and start Teleport
systemctl enable teleport
systemctl start teleport