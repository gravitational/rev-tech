output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Database Access — PostgreSQL (Self-Managed)
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the instance to boot and register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List databases:
       tsh db ls env=${var.env},team=${var.team}

    3. Connect as reader (no password — mTLS cert issued by Teleport):
       tsh db connect postgres-${var.env} --db-user=reader

    4. Connect as writer:
       tsh db connect postgres-${var.env} --db-user=writer

    ──────────────────────────────────────────────────────
    Database: postgres-${var.env}
    Protocol: PostgreSQL wire protocol, mTLS
    ──────────────────────────────────────────────────────
  EOT
}
