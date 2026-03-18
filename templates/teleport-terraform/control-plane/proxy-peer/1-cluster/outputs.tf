output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "subnet_id" {
  value       = aws_subnet.main.id
  description = "Subnet ID"
}

output "security_group_id" {
  value       = aws_security_group.main.id
  description = "Security group ID for Teleport instances"
}

output "ami_id" {
  value       = data.aws_ami.main.id
  description = "Amazon Linux 2023 AMI ID"
}

output "bucket_name" {
  value       = aws_s3_bucket.main.bucket
  description = "S3 bucket used for join token/user invite"
}

output "instance_profile_name" {
  value       = aws_iam_instance_profile.ec2_profile.name
  description = "Instance profile name for Teleport EC2 instances"
}

output "username" {
  value       = local.username
  description = "Lowercased username for naming"
}
