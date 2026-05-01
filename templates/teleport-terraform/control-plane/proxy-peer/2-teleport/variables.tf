variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to deploy into"
}

variable "user" {
  type        = string
  description = "SSO username; used for Teleport purposes (e.g. jsmith@example.com)"
}

variable "env" {
  description = "Environment label (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Team label (e.g., platform, dev)"
  type        = string
  default     = "platform"
}

variable "parent_domain" {
  type        = string
  description = "Domain to create Teleport cluster off of (e.g. example.com)"
}

variable "proxy_address" {
  type        = string
  description = "Fully qualified domain name of Teleport cluster (e.g. teleport.example.com)"
}

variable "license_path" {
  type        = string
  default     = ""
  description = "Path to Teleport Enterprise license file (PEM). Leave empty for no license."
}

variable "teleport_version" {
  type        = string
  description = "Full version of Teleport to use (e.g. 18.4.1)"
}

variable "proxy_count" {
  type        = number
  default     = 1
  description = "Number of proxy peers to create"
}

variable "ec2main_size" {
  type        = string
  default     = "t3.small"
  description = "Size of EC2 instance for auth/proxy"
}

variable "ec2proxy_size" {
  type        = string
  default     = "t3.micro"
  description = "Size of EC2 instance for proxy peers"
}
