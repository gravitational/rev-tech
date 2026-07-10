output "cluster_url" {
  value       = "https://${var.proxy_address}"
  description = "Teleport cluster URL"
}

output "public_ip" {
  value       = aws_instance.main.public_ip
  description = "Public IP of the Teleport instance"
}

output "initial_user_command" {
  value       = "aws s3 cp s3://${data.terraform_remote_state.cluster.outputs.bucket_name}/user -"
  description = "Command to retrieve the initial admin user invite link"
}
