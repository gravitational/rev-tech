output "connection_guide" {
  description = "Quick-reference tsh commands for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: Dev Demo — Developer Day in the Life
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    Teleport: ${var.teleport_version}
    ──────────────────────────────────────────────────────

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. SSH nodes (Bob sees dev only — prod requires access request):
       tsh ls env=${var.env},team=${var.team}
       tsh ssh ec2-user@<dev-node>

    3. Databases (cert auth — no passwords):
       tsh db ls env=${var.env},team=${var.team}
       tsh db connect postgres-${var.env} --db-user=writer
       tsh db connect mongodb-${var.env} --db-user=writer

    4. Applications:
       tsh apps ls env=${var.env},team=${var.team}
       tsh apps login grafana-${var.env}
       tsh apps login httpbin-${var.env}

    5. MCP / AI integration:
       tsh mcp ls
       tsh mcp config mcp-filesystem-${var.env}
       # Paste into Claude Desktop or Cursor

    6. Access request demo (as Bob):
       tsh request create --roles=prod-readonly-access --reason="check prod logs"
       # engineer approves → tsh ls now shows prod-${var.prod_env}
       tsh ssh ec2-user@<prod-node>

    7. Windows Desktop (web UI only):
       https://${var.proxy_address}/web/desktops

    8. Audit trail:
       tsh recordings ls

    ──────────────────────────────────────────────────────
    Dev nodes: 2 (env=${var.env})  |  Prod node: 1 (env=${var.prod_env})
    DBs: postgres-${var.env}, mongodb-${var.env}
    Apps: grafana-${var.env}, httpbin-${var.env}, mcp-filesystem-${var.env}
    Cost: ~$5–7/day — destroy when done: terraform destroy
    ──────────────────────────────────────────────────────
  EOT
}
