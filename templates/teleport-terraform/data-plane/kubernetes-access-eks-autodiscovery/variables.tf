variable "proxy_address" {
  description = "Teleport proxy address (host only, no https or port)"
  type        = string
}

variable "user" {
  description = "Username or email for resource tagging and naming"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the agent"
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

variable "discovery_regions" {
  description = <<-EOT
    AWS regions to scan for EKS clusters. Defaults to [var.region] (agent's region).
    Expand to discover cross-region clusters, e.g.:
      ["us-west-2", "eu-west-2"]   — specific regions
      ["*"]                         — all regions
  EOT
  type        = list(string)
  default     = null
}

variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "CIDR block for the public subnet (NAT gateway)"
  type        = string
  default     = "10.0.0.0/24"
}
