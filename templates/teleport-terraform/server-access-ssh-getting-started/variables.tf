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

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "team" {
  description = "Team label for SSH nodes (e.g., platform, sre, app-team)"
  type        = string
  # default     = "platform"
}

variable "teleport_version" {
  description = "Teleport version to install on nodes"
  type        = string
  # default     = "18.0.0"
}

variable "user" {
  description = "Username or identifier for resource tagging"
  type        = string
}
