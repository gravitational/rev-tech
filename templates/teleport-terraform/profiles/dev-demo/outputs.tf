output "connection_guide" {
  description = "Quick-reference tsh commands for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Profile: Dev Demo — Developer Day in the Life
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    1. Login:
       tsh login --proxy=${var.proxy_address}:443
    %{~if var.create_demo_rbac}
       # as the developer persona (activate first — see the demo_user_setup output):
       tsh login --proxy=${var.proxy_address}:443 --user=${var.demo_user_name} --auth=local
    %{~endif}

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

    6. Access request demo (as ${var.demo_user_name}):
       tsh request create --roles=${var.create_demo_rbac ? "${local.user_prefix}-prod-readonly" : "prod-readonly-access"} --reason="check prod logs"
       # approver: tsh request review <request-id> --approve --reason="ok"
       # then: tsh ls shows ${var.prod_env}-ssh-0
       tsh ssh ec2-user@${var.prod_env}-ssh-0

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

output "demo_user_setup" {
  description = "One-time activation steps for the demo user (null when create_demo_rbac is false)"
  value       = var.create_demo_rbac ? module.demo_rbac[0].demo_user_setup : null
}
