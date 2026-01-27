output "mcp_app_name" {
  description = "Name of the MCP app"
  value       = module.mcp_stdio_app.app_name
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
