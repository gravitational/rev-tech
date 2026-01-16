variable "env" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Creator tag (e.g., email or username)"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address (without https)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install (e.g., 17.3.3)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the instance"
  type        = list(string)
}

variable "team" {
  description = "Team label for Machine ID automation"
  type        = string
  default     = "engineering"
}