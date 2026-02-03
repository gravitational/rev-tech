##################################################################################
# OUTPUTS
##################################################################################

output "teleport_url" {
  description = "Teleport demo URL"
  value       = var.domain_name != "" ? "https://${var.proxy_address}" : "https://${try(data.kubernetes_service.teleport_cluster.status[0].load_balancer[0].ingress[0].hostname, "pending")}" 
}

output "teleport_version" {
  description = "Deployed Teleport version"
  value       = var.teleport_version
}

output "cluster_name" {
  description = "Teleport cluster name"
  value       = var.proxy_address
}

output "eks_cluster_name" {
  description = "EKS cluster name from remote state"
  value       = local.cluster_name
}

output "dynamodb_backend_table" {
  description = "DynamoDB backend table name"
  value       = aws_dynamodb_table.teleport_backend.name
}

output "dynamodb_events_table" {
  description = "DynamoDB events table name"
  value       = aws_dynamodb_table.teleport_events.name
}

output "s3_session_recordings_bucket" {
  description = "S3 bucket for session recordings"
  value       = aws_s3_bucket.session_recordings.id
}

output "certificate_status" {
  description = "Commands to check certificate status"
  value = {
    check_certificate   = "kubectl describe certificate teleport-tls -n teleport-cluster"
    check_secret        = "kubectl describe secret teleport-tls -n teleport-cluster"
    cert_manager_logs   = "kubectl logs -n cert-manager deployment/cert-manager"
    certificate_details = "kubectl get certificate -n teleport-cluster teleport-tls -o yaml"
  }
}
