output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Database Access — MySQL (Self-Managed)
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the instance to boot and register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List databases:
       tsh db ls env=${var.env},team=${var.team}

    3. Connect as alice (no password — mTLS cert issued by Teleport):
       tsh db connect mysql-${var.env} --db-user=alice

    4. Connect as bob:
       tsh db connect mysql-${var.env} --db-user=bob

    ──────────────────────────────────────────────────────
    Database: mysql-${var.env}
    Protocol: MySQL wire protocol, mTLS
    ──────────────────────────────────────────────────────
  EOT
}
