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
