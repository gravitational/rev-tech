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
  description = "Teleport version to install"
  type        = string
}

variable "region" {
  description = "AWS region to deploy the agent into"
  type        = string
}

variable "discovery_regions" {
  description = <<-EOT
    AWS regions the discovery service will scan for EKS clusters.
    Defaults to [var.region] (same region as the agent).
    Set to multiple regions to discover cross-region clusters:
      discovery_regions = ["us-west-2", "eu-west-2"]
    Set to ["*"] to scan all regions.
  EOT
  type        = list(string)
  default     = null
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

variable "eks_tag_key" {
  description = "AWS tag key used to select EKS clusters for auto-discovery"
  type        = string
  default     = "teleport-discovery"
}

variable "eks_tag_value" {
  description = "AWS tag value used to select EKS clusters for auto-discovery"
  type        = string
  default     = "enabled"
}
