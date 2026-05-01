variable "env" {
  description = "Environment label"
  type        = string
}

variable "team" {
  description = "Team label for Teleport RBAC"
  type        = string
}

variable "user" {
  description = "Creator email; username portion used for resource naming"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address (host only, no https or port)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the agent"
  type        = string
}

variable "region" {
  description = "AWS region to scan for EC2 instances"
  type        = string
}

variable "ami_id" {
  description = "AMI for the agent instance (Amazon Linux 2023 recommended)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "subnet_id" {
  description = "Subnet where the agent runs"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups to attach to the agent instance"
  type        = list(string)
}

variable "tags" {
  description = "Additional AWS tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ec2_tag_key" {
  description = "AWS tag key used to select EC2 instances for auto-discovery"
  type        = string
  default     = "teleport-discovery"
}

variable "ec2_tag_value" {
  description = "AWS tag value used to select EC2 instances for auto-discovery"
  type        = string
  default     = "enabled"
}

variable "target_iam_role_name" {
  description = "Name of the IAM role attached to target EC2 instances; used to scope the IAM join token"
  type        = string
}
