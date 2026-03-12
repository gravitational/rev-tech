variable "agent_count" {
  description = "Number of SSH nodes to create"
  type        = number
  default     = 3
}

variable "env" {
  description = "Environment label (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type for SSH nodes"
  type        = string
  default     = "t3.micro"
}

variable "proxy_address" {
  description = "Teleport Proxy address (host only, no https or port)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the nodes"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "team" {
  description = "Team label for SSH nodes (e.g., platform, sre, app-team)"
  type        = string
  default     = "platform"
}

variable "user" {
  description = "Username or identifier for resource tagging"
  type        = string
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
