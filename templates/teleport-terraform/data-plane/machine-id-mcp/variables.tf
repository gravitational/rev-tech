variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "env" {
  description = "Environment label (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Username or identifier for resource tagging"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address (host only, no https)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install"
  type        = string
}

variable "team" {
  description = "Team label for MCP server"
  type        = string
  default     = "platform"
}

variable "instance_type" {
  description = "EC2 instance type for MCP server"
  type        = string
  default     = "t3.small"
}

variable "bot_name_prefix" {
  description = "Prefix for Machine ID bot name. A short random suffix is appended per deployment."
  type        = string
  default     = "mcp-bot"
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
