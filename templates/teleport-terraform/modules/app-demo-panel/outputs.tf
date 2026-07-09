output "private_ip" {
  description = "Private IP of the demo panel instance"
  value       = aws_instance.demo_panel.private_ip
}
