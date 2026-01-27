variable "env" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install"
  type        = string
}

variable "user" {
  description = "Creator tag"
  type        = string
}

variable "bot_name" {
  description = "Name of the Machine ID bot"
  type        = string
  default     = "ansible"
}

variable "role_name" {
  description = "Name of the Teleport role to create"
  type        = string
}

variable "allowed_logins" {
  description = "System users that this role is allowed to log in as"
  type        = list(string)
}

variable "node_labels" {
  description = "Node labels the role should have access to"
  type        = map(list(string))
}
