variable "proxy_address" {
  description = "Teleport proxy address (host only, no https or port)"
  type        = string
}

variable "user" {
  description = "Username or email for resource tagging and naming"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on all nodes"
  type        = string
}

variable "env" {
  description = "Environment label (e.g., dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Team label for Teleport RBAC"
  type        = string
  default     = "platform"
}

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-2"
}

variable "console_role_arns" {
  description = "IAM role ARNs the AWS Console app host is allowed to assume"
  type        = list(string)
  default     = []
}

variable "cidr_vpc" {
  description = "CIDR block for the shared VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for the primary private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "CIDR block for the public subnet (NAT gateway)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "cidr_secondary_subnet" {
  description = "CIDR block for the secondary private subnet (required for RDS multi-AZ)"
  type        = string
  default     = "10.0.2.0/24"
}
