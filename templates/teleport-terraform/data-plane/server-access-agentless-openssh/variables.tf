variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "user" {
  description = "Your email — used for tagging"
  type        = string
}

variable "env" {
  description = "Environment label"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Team label"
  type        = string
  default     = "dev"
}

variable "node_count" {
  description = "Number of agentless EC2 instances to create"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh_login" {
  description = "OS user to create on agentless hosts — must match the login in the Teleport role"
  type        = string
  default     = "teleport-user"
}

variable "cidr_vpc" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "Private subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.0.0/24"
}
