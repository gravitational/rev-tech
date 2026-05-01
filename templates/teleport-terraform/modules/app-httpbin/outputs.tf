output "httpbin_private_ip" {
  description = "Private IP of the httpbin instance"
  value       = aws_instance.httpbin.private_ip
}
