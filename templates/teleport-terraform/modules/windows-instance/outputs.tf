output "private_ip" {
  description = "Private IP address of Windows instance"
  value       = aws_instance.windows.private_ip
}

output "private_dns" {
  description = "Private DNS name of Windows instance"
  value       = aws_instance.windows.private_dns
}

output "hostname" {
  description = "name of instance"
  value       = aws_instance.windows.tags["Name"]
}
