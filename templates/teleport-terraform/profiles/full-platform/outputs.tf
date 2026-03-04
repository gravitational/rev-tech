output "connection_guide" {
  description = "Quick-reference tsh commands for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: Full Platform Demo
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. SSH nodes:
       tsh ls env=${var.env},team=${var.team}

    3. Databases:
       tsh db ls env=${var.env},team=${var.team}
       tsh db connect postgres-${var.env}
       tsh db connect mongodb-${var.env}
       tsh db connect rds-mysql-${var.env}

    4. Applications:
       tsh apps ls env=${var.env},team=${var.team}
       tsh apps login grafana-${var.env}
       tsh apps login awsconsole-${var.env}

    5. Windows Desktop:
       tsh desktop ls env=${var.env},team=${var.team}

    6. MCP / Machine ID:
       tsh mcp ls env=${var.env},team=${var.team}

    ──────────────────────────────────────────────────────
    NOTE: ~$5-10/day in AWS costs. Destroy when done:
       terraform destroy
    ──────────────────────────────────────────────────────
  EOT
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint address"
  value       = module.rds_mysql.rds_endpoint
}
