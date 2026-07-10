output "instance_id" {
  description = "ID of the shared AWS console app host instance"
  value       = aws_instance.app_host.id
}

output "public_ip" {
  description = "Public IP of the shared AWS console app host"
  value       = aws_instance.app_host.public_ip
}

output "iam_role_arn" {
  description = "IAM role ARN used by the shared AWS console app host (instance profile principal)"
  value       = aws_iam_role.app_host.arn
}
