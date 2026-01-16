#!/bin/bash
set -euxo pipefail

# Set hostname
hostnamectl set-hostname "${env}-rds-mysql-agent"

# Update system and install dependencies
dnf update -y
dnf install -y mariadb105 jq nmap-ncat

########################################################
# Teleport Installation 
########################################################
curl "https://${proxy_address}/scripts/install.sh" | bash -s "${teleport_version}" enterprise

#########################################################
# Wait for RDS to be available and configure MySQL
#########################################################
echo "Waiting for RDS instance to be available..."

# Wait for RDS instance to be ready
echo "Checking RDS instance status..."
RDS_INSTANCE_ID="${rds_instance_id}"
for i in {1..30}; do
    echo "Status check attempt $i/30..."
    STATUS=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" --region "${region}" --query 'DBInstances[0].DBInstanceStatus' --output text)
    if [ "$STATUS" = "available" ]; then
        echo "✓ RDS instance is available"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "✗ RDS instance not available after 30 attempts"
        exit 1
    fi
    sleep 30
done

# Extract hostname without port
RDS_HOSTNAME=$(echo "${rds_endpoint}" | cut -d':' -f1)

# Test direct connection with password first
echo "Testing direct RDS connection with password..."
for i in {1..10}; do
    echo "Connection attempt $i/10..."
    if mysql -h "$RDS_HOSTNAME" -u admin -p'${rds_password}' --ssl -e "SELECT 1;" 2>/dev/null; then
        echo "✓ Direct RDS connection successful"
        break
    else
        echo "MySQL connection failed. Testing network connectivity..."
        # Test if we can reach the RDS endpoint
        nc -zv "$RDS_HOSTNAME" 3306 2>&1 || echo "Network connectivity test failed"
        # Show any MySQL error
        mysql -h "$RDS_HOSTNAME" -u admin -p'${rds_password}' --ssl -e "SELECT 1;" 2>&1 | head -3
    fi
    if [ $i -eq 10 ]; then
        echo "✗ Failed to connect to RDS after 10 attempts"
        exit 1
    fi
    sleep 15
done

echo "Configuring MySQL for Teleport auto user provisioning..."

# Configure MySQL for auto user provisioning with direct RDS access
mysql -h "$RDS_HOSTNAME" -u admin -p'${rds_password}' --ssl << 'SQLEOF'
-- Create teleport-admin user with AWS IAM authentication
CREATE USER 'teleport-admin' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';

-- Grant required permissions for auto user provisioning
GRANT SELECT ON mysql.role_edges TO 'teleport-admin';
GRANT PROCESS, ROLE_ADMIN, CREATE USER ON *.* TO 'teleport-admin';

-- Create teleport database/schema (if not exists)
CREATE DATABASE IF NOT EXISTS `teleport`;

-- Grant routine permissions for stored procedures
GRANT ALTER ROUTINE, CREATE ROUTINE, EXECUTE ON `teleport`.* TO 'teleport-admin';

-- Create MySQL roles that Teleport expects to use
CREATE ROLE IF NOT EXISTS 'dbadmin';
CREATE ROLE IF NOT EXISTS 'reader';
CREATE ROLE IF NOT EXISTS 'writer';

-- Grant permissions to these roles (RDS-compatible privileges)
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, CREATE TEMPORARY TABLES, LOCK TABLES, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EXECUTE, TRIGGER, EVENT ON *.* TO 'dbadmin';
GRANT SELECT, SHOW VIEW ON *.* TO 'reader';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE ON *.* TO 'writer';

-- Allow teleport-admin to grant these roles to auto-provisioned users
GRANT 'dbadmin' TO 'teleport-admin' WITH ADMIN OPTION;
GRANT 'reader' TO 'teleport-admin' WITH ADMIN OPTION;
GRANT 'writer' TO 'teleport-admin' WITH ADMIN OPTION;

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Verify the user was created
SELECT user, host, plugin FROM mysql.user WHERE user = 'teleport-admin';
SQLEOF

if [ $? -eq 0 ]; then
    echo "✓ MySQL auto user provisioning configuration completed successfully"
else
    echo "✗ MySQL configuration failed"
    exit 1
fi

#########################################################
# Teleport Configuration
#########################################################
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

auth_service:
  enabled: "no"

ssh_service:
  enabled: "yes"
  labels:
    tier: "${env}"
    team: "${team}"

proxy_service:
  enabled: "no"

app_service:
  enabled: "no"
EOF

systemctl enable teleport
systemctl restart teleport