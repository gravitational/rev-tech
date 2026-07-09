variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "subnet" {
  type        = string
  default     = "10.0.0.0/24"
  description = "Subnet CIDR for the public subnet"
}

variable "region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to deploy into"
}

variable "user" {
  type        = string
  description = "User email for tagging and resource naming (e.g. you@example.com)"
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
