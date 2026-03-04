output "connection_guide" {
  description = "Quick-reference tsh commands for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: Windows + MongoDB + SSH
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. SSH nodes:
       tsh ls env=${var.env},team=${var.team}
       tsh ssh ec2-user@<node-name>

    3. MongoDB:
       tsh db ls env=${var.env},team=${var.team}
       tsh db connect mongodb-${var.env} --db-user=teleport --db-name=test

    4. Windows Desktop:
       Open the Teleport Web UI → Resources → filter by Desktops
       (Desktop connections require the Web UI or Teleport Connect app)

    ──────────────────────────────────────────────────────
  EOT
}
