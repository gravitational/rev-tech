output "connection_guide" {
  description = "Quick-reference tsh commands and next steps for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Application Access — Demo Panel
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 2–3 minutes after apply for the instance to boot and register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List apps:
       tsh apps ls env=${var.env},team=${var.team}

    3. Open the demo panel:
       tsh apps login demo-panel-${var.env}
       # Browser opens: shows your Teleport identity (username, roles, traits)

    ──────────────────────────────────────────────────────
    App: demo-panel-${var.env}
    App repo: ${var.app_repo}
    ──────────────────────────────────────────────────────
  EOT
}
