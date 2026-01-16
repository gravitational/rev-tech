variable "region" {
  description = "AWS region to deploy MySQL in"
  type        = string
}

variable "env" {
  description = "Environment label (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Tag to associate with deployed resources"
  type        = string
}

variable "proxy_address" {
  description = "Teleport Proxy address (without https)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the MySQL host"
  type        = string
}

variable "team" {
  description = "Team label for RBAC"
  type        = string
}