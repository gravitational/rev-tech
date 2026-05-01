output "grafana_private_ip" {
  description = "Private IP of the Grafana instance"
  value       = aws_instance.grafana.private_ip
}