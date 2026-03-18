output "instance_id" {
  value = aws_instance.desktop_service.id
}

output "private_ip" {
  value = aws_instance.desktop_service.private_ip
}