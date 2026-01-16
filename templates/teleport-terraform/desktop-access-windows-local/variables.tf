variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "env" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Username or identifier for resource tagging"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address (host:port)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install"
  type        = string
}