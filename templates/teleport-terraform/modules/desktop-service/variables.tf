variable "env" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Tag value for resource creator"
}


variable "proxy_address" {
  description = "Teleport proxy address (host:port)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install (e.g., 17.4.8)"
  type        = string
}

variable "windows_hosts" {
  description = "List of Windows desktops to register with"
  type = list(object({
    name    = string
    address = string
  }))
}

variable "ami_id" {
  description = "AMI ID for Amazon Linux 2023"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "Subnet ID to launch instance in"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
}

variable "team" {
  description = "Team label for desktop service"
  type        = string
  default     = "engineering"
}

variable "windows_internal_dns" {
  description = "private dns of windows host"
  type        = string
}