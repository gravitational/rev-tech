variable "agent_count" {
  description = "Number of SSH nodes to deploy"
  type        = number
}

variable "ami_id" {
  description = "AMI to use for SSH nodes"
  type        = string
}

variable "env" {
  description = "Environment label"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
}

variable "proxy_address" {
  description = "Teleport Proxy address"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the node"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
}

variable "subnet_id" {
  description = "Subnet ID to use"
  type        = string
}

variable "team" {
  description = "Team label for SSH nodes"
  type        = string
}

variable "user" {
  description = "Creator tag"
  type        = string
}

variable "tags" {
  description = "Additional tags to attach to each instance"
  type        = map(string)
  default     = {}
}
