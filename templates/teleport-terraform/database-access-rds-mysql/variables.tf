variable "region" {
  description = "AWS region to deploy MySQL in"
  type        = string
  default     = "us-east-2"
}

variable "proxy_address" {
  type        = string
  description = "Host of the Teleport Proxy Service"
}

variable "teleport_version" {
  type        = string
  description = "Version of Teleport to install on each agent"
}

variable "user" {
  type        = string
  description = "username assigned in description for AWS resources"
}

variable "env" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
  default     = "dev"
}

variable "cidr_vpc" {
  description = "CIDR block for VPC"
  default     = "10.1.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for private subnet"
  default     = "10.1.0.0/20"
}

variable "cidr_public_subnet" {
  description = "CIDR block for public subnet"
  default     = "10.1.16.0/20"
}

variable "cidr_secondary_subnet" {
  description = "CIDR block for secondary private subnet (for RDS)"
  default     = "10.1.32.0/20"
}