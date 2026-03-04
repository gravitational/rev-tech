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

variable "team" {
  type        = string
  description = "Team label for Machine ID automation"
  default     = "platform"
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
