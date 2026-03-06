output "mcp_app_name" {
  description = "Name of the MCP app resource in Teleport"
  value       = "mcp-everything-${var.env}"
}

output "bot_name" {
  description = "Generated Machine ID bot name"
  value       = module.machineid_bot.bot_name
}
