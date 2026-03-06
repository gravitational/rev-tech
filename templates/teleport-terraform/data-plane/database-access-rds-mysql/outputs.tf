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

    3. Connect (no password — Teleport issues a short-lived cert; auto-user created on first connect):
       tsh db connect rds-mysql-${var.env} --db-user=alice

    4. Connect as a different role:
       tsh db connect rds-mysql-${var.env} --db-user=bob

    ──────────────────────────────────────────────────────
    Database: rds-mysql-${var.env}
    RDS endpoint: (see rds_endpoint output)
    Auto-user provisioning: enabled — Teleport creates DB users on first connect
    ──────────────────────────────────────────────────────
  EOT
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds_mysql.rds_endpoint
}
