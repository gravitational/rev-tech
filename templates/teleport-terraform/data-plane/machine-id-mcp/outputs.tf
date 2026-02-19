output "mcp_app_name" {
  description = "Name of the MCP app resource in Teleport"
  value       = "mcp-everything-${var.env}"
}

output "mcp_app_public_ip" {
  description = "Public IP of the MCP server instance"
  value       = module.mcp_stdio_app.public_ip
}

output "bot_token" {
  description = "Provision token for the Machine ID bot"
  value       = module.machineid_bot.bot_token
  sensitive   = true
}

output "bot_name" {
  description = "Generated Machine ID bot name"
  value       = module.machineid_bot.bot_name
}
