output "connection_guide" {
  description = "Quick-reference tsh commands and MCP client setup for the demo"
  value       = <<-EOT
    ──────────────────────────────────────────────────────
    Template: Machine ID + MCP (filesystem)
    Cluster: ${var.proxy_address}  |  env=${var.env}  |  team=${var.team}
    ──────────────────────────────────────────────────────

    Allow 3–5 minutes after apply for the MCP server to register.

    1. Login:
       tsh login --proxy=${var.proxy_address}:443

    2. List MCP servers:
       tsh mcp ls

    3. Get MCP client config (paste into Claude Desktop, Cursor, etc.):
       tsh mcp config mcp-filesystem-${var.env}

    4. Demo prompts to try:
       - "List the files in /demo-files"
       - "Read config/app.yaml and identify any security concerns"
       - "Analyze logs/recent.log and flag anything suspicious"

    5. Verify every tool call is in the audit log:
       tsh recordings ls

    ──────────────────────────────────────────────────────
    MCP app:  mcp-filesystem-${var.env}
    Bot name: (see bot_name output)
    Files exposed: /demo-files (read-only)
    ──────────────────────────────────────────────────────
  EOT
}

output "mcp_app_name" {
  description = "Name of the MCP app resource in Teleport"
  value       = "mcp-filesystem-${var.env}"
}

output "bot_name" {
  description = "Generated Machine ID bot name"
  value       = module.machineid_bot.bot_name
}
