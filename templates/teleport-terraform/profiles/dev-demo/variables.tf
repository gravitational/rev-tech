variable "proxy_address" {
  description = "Teleport proxy address (host only, no https or port)"
  type        = string
}

variable "user" {
  description = "Username or email for resource tagging and naming"
  type        = string
}

variable "env" {
  description = "Environment label for dev resources (e.g., dev)"
  type        = string
  default     = "dev"
}

variable "prod_env" {
  description = "Environment label for the prod SSH node used in the access request demo"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Team label for Teleport RBAC"
  type        = string
  default     = "platform"
}

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-2"
}

variable "cidr_vpc" {
  description = "CIDR block for the shared VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for the primary private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "CIDR block for the public subnet (NAT gateway)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "create_demo_rbac" {
  description = "Create the demo roles (user-prefixed) and local demo user this profile's narrative uses. Set to false if your cluster already has the control-plane RBAC roles."
  type        = bool
  default     = true
}

variable "demo_user_name" {
  description = "Name of the local demo user (developer persona). Usernames are cluster-global — override on shared clusters."
  type        = string
  default     = "bob"
}
