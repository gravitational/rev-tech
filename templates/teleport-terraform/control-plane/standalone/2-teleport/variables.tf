variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to deploy into"
}

variable "user" {
  type        = string
  description = "User email for tagging and Teleport admin user creation (e.g. you@example.com)"
}

variable "env" {
  type        = string
  default     = "dev"
  description = "Environment label"
}

variable "team" {
  type        = string
  default     = "platform"
  description = "Team label"
}

variable "domain_name" {
  type        = string
  description = "Route 53 hosted zone domain (e.g. example.com)"
}

variable "proxy_address" {
  type        = string
  description = "Fully qualified domain name of the Teleport cluster (e.g. teleport.example.com)"
}

variable "teleport_version" {
  type        = string
  default     = "18.7.1"
  description = "Teleport version to install"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the Teleport node"
}

variable "license_path" {
  type        = string
  default     = ""
  description = "Path to Teleport Enterprise license file (PEM). Leave empty for Community Edition."
}
