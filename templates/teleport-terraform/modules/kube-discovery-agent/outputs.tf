output "instance_id" {
  description = "EC2 instance ID of the Teleport Kubernetes discovery agent"
  value       = aws_instance.agent.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the agent (needed to grant it EKS access)"
  value       = aws_iam_role.agent.arn
}

output "iam_role_name" {
  description = "Name of the IAM role (useful for adding inline policies)"
  value       = aws_iam_role.agent.name
}

output "discovery_group" {
  description = "Teleport discovery group name used by this agent"
  value       = local.group_name
}
