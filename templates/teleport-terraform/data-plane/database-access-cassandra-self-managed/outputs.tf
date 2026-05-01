output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Database Access — Cassandra (Self-Managed)
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the instance to boot and register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List databases:
       tsh db ls env=${var.env},team=${var.team}

    3. Connect (no password — mTLS cert issued by Teleport):
       tsh db connect cassandra-${var.env} --db-user=writer

    4. Query at the cqlsh prompt:
       USE dev;
       DESCRIBE TABLES;

    ──────────────────────────────────────────────────────
    Database: cassandra-${var.env}
    Protocol: Cassandra native (port 9042), mTLS
    ──────────────────────────────────────────────────────
  EOT
}
