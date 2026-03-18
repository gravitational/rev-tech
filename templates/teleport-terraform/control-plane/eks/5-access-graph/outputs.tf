output "access_graph_endpoint" {
  value       = "teleport-access-graph.teleport-access-graph.svc.cluster.local:443"
  description = "Access Graph gRPC endpoint (internal Kubernetes DNS)"
}

output "rds_endpoint" {
  value       = aws_rds_cluster.access_graph.endpoint
  description = "RDS Aurora cluster endpoint"
}

output "next_steps" {
  value       = <<-EOT
    Access Graph deployed. To enable it in Teleport:

      1. Re-apply 2-teleport with Access Graph enabled:

           cd ../2-teleport
           TF_VAR_access_graph_enabled=true terraform apply

      2. Access in Teleport Web UI:
           Identity Security → Graph Explorer

      Note: Users with the platform-dev-access role can view Access Graph.
      Engineers (who hold that role standing) see it immediately after login.
  EOT
  description = "Post-deployment instructions"
}
