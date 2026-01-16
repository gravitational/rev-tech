variable "env" {
  type        = string
  description = "Environment label (e.g., dev)"
}

variable "user" {
  type        = string
  description = "Resource creator email"
}

variable "proxy_address" {
  type        = string
  description = "Teleport proxy domain"
}

variable "teleport_version" {
  type        = string
  description = "Teleport version to install"
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources"
}
