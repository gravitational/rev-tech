output "provision_token" {
  description = "Provision token for all SSH agents"
  value       = teleport_provision_token.agent.metadata.name
}

output "private_ips" {
  description = "Private IPs of deployed SSH nodes"
  value       = aws_instance.ssh_node[*].private_ip
}
