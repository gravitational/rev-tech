output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Database Access — MongoDB (Self-Managed)
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the instance to boot and register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List databases:
       tsh db ls env=${var.env},team=${var.team}

    3. Connect as reader (no password — mTLS cert issued by Teleport):
       tsh db connect mongodb-${var.env} --db-user=reader --db-name=dev

    4. Connect as writer:
       tsh db connect mongodb-${var.env} --db-user=writer --db-name=dev

    ──────────────────────────────────────────────────────
    Database: mongodb-${var.env}
    Protocol: MongoDB wire protocol, mTLS
    ──────────────────────────────────────────────────────
  EOT
}
