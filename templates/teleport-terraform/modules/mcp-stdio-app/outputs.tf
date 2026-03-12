output "instance_id" {
  description = "ID of the MCP server instance"
  value       = aws_instance.mcp_app.id
}

output "public_ip" {
  description = "Public IP of the MCP server instance"
  value       = aws_instance.mcp_app.public_ip
}

output "app_name" {
  description = "MCP app name"
  value       = var.app_name
}
