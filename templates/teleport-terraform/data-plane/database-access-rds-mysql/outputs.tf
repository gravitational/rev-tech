output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Database Access — RDS MySQL
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the RDS instance and agent to register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List databases:
       tsh db ls env=${var.env},team=${var.team}

    3. Connect — use YOUR Teleport username as db-user (not reader/writer).
       Teleport creates a MySQL user for you on first connect and assigns
       the db_roles from your Teleport role (reader, writer, dbadmin):
       tsh db connect rds-mysql-${var.env} --db-user=<your-teleport-username>

       Example (replace with actual login):
       tsh db connect rds-mysql-${var.env} --db-user=engineer@example.com

    4. Run a query:
       show databases;
       select user, host from mysql.user;

    ──────────────────────────────────────────────────────
    Database: rds-mysql-${var.env}
    RDS endpoint: (see rds_endpoint output)
    Auth: IAM auth via teleport-admin — no passwords, auto user provisioning
    MySQL roles available: reader, writer, dbadmin
    ──────────────────────────────────────────────────────
  EOT
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds_mysql.rds_endpoint
}
