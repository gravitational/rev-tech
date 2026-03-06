variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "user" {
  description = "Tag value for resource creator"
  type        = string
}

variable "proxy_address" {
  description = "Teleport Proxy address (host only, no https://)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install"
  type        = string
}

variable "app_repo" {
  description = "Git URL for the demo panel Flask app (e.g. https://github.com/org/app-demo-panel)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for Amazon Linux 2023"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "team" {
  description = "Team label for the demo panel application"
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Additional tags to attach to each instance"
  type        = map(string)
  default     = {}
}
