output "teleport_user_login_details" {
  value       = "aws s3 cp s3://${data.terraform_remote_state.cluster.outputs.bucket_name}/user -"
  description = "Command to retrieve the initial Teleport user login details"
}

output "auth_public_ip" {
  value       = aws_instance.main.public_ip
  description = "Public IP for the auth/proxy instance"
}
