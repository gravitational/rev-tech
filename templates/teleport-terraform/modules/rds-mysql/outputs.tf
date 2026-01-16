output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.mysql.identifier
}

output "database_name" {
  description = "Teleport database resource name"
  value       = teleport_database.rds_mysql.metadata.name
}

output "agent_private_ip" {
  description = "Teleport agent private IP"
  value       = aws_instance.agent.private_ip
}