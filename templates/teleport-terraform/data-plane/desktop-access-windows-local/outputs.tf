output "connection_guide" {
  description = "Quick-reference access instructions for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Desktop Access — Windows
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Windows Desktop Access is web UI only — no tsh command, no RDP client.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. Open the Teleport Web UI and navigate to Windows Desktops:
       https://${var.proxy_address}/web/desktops

    3. Click Connect on the listed Windows desktop — RDP session opens in the browser.

    ──────────────────────────────────────────────────────
    Windows host: ${var.env}-windows (accessible via Web UI only)
    Desktop service: Linux agent bridging RDP to Teleport
    ──────────────────────────────────────────────────────
  EOT
}
