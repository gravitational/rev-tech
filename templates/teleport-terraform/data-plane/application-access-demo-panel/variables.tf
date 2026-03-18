variable "region" {
  description = "AWS region to deploy in"
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
  description = "Teleport version to install"
  type        = string
}

variable "app_repo" {
  description = "Git URL for the demo panel Flask app"
  type        = string
  default     = "https://github.com/tenaciousdlg/app-demo-panel"
}

variable "team" {
  description = "Team label for RBAC"
  type        = string
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
