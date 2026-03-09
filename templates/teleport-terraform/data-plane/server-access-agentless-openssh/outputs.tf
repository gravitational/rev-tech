output "node_public_ips" {
  value       = aws_instance.node[*].public_ip
  description = "Public IP addresses of the agentless nodes"
}

output "teleport_node_names" {
  value       = teleport_server.node[*].metadata.name
  description = "Teleport node names as registered (account-id/instance-id)"
}

output "connection_guide" {
  value       = <<-EOT
    Nodes registered. To SSH via Teleport:

      tsh ls                                     # confirm nodes appear
      tsh ssh ${var.ssh_login}@agentless-0.${var.env}   # connect to first node

    The Teleport proxy routes the connection — no direct network access required.

    To view sessions and audit events:
      tsh recordings ls
  EOT
  description = "How to connect to the agentless nodes"
}
