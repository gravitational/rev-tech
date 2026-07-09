output "instance_id" {
  description = "EC2 instance ID of the Teleport EC2 discovery agent"
  value       = aws_instance.agent.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the discovery agent"
  value       = aws_iam_role.agent.arn
}

output "join_token_name" {
  description = "Name of the IAM join token used by auto-discovered EC2 instances"
  value       = local.token_name
}

output "discovery_group" {
  description = "Teleport discovery group name used by this agent"
  value       = local.group_name
}
