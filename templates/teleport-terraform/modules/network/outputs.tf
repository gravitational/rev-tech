output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the VPC"
}

output "subnet_id" {
  value       = aws_subnet.private.id
  description = "ID of the private subnet"
}

output "security_group_id" {
  value       = aws_security_group.default.id
  description = "ID of the default security group"
}

# New outputs for RDS support
output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "ID of the public subnet"
}

output "private_subnet_ids" {
  value       = var.create_secondary_subnet ? [aws_subnet.private.id, aws_subnet.private_secondary[0].id] : [aws_subnet.private.id]
  description = "IDs of all private subnets"
}

output "db_subnet_group_name" {
  value       = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : null
  description = "Name of the DB subnet group"
}