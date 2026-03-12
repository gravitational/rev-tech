output "connection_guide" {
  description = "Quick-reference tsh commands for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: Cloud-Native Apps
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    Teleport: ${var.teleport_version}
    ──────────────────────────────────────────────────────

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. Applications:
       tsh apps ls env=${var.env},team=${var.team}
       tsh apps login grafana-${var.env}
       tsh apps login httpbin-${var.env}
       tsh apps login awsconsole-${var.env}

    3. RDS MySQL:
       tsh db ls env=${var.env},team=${var.team}
       tsh db connect rds-mysql-${var.env}

    4. Inspect JWT headers (Grafana demo):
       tsh apps login httpbin-${var.env}
       curl $(tsh apps config --format=uri httpbin-${var.env})/headers

    ──────────────────────────────────────────────────────
  EOT
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint address"
  value       = module.rds_mysql.rds_endpoint
}
