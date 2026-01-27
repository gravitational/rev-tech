variable "bot_name" {
  description = "Name of the Machine ID bot"
  type        = string
}

variable "role_name" {
  description = "Name of the Teleport role to create"
  type        = string
}

variable "allowed_logins" {
  description = "System users that this role is allowed to log in as"
  type        = list(string)
  default     = []
}

variable "node_labels" {
  description = "Node labels the role should have access to"
  type        = map(list(string))
  default     = {}
}

variable "app_labels" {
  description = "App labels the role should have access to"
  type        = map(list(string))
  default     = {}
}

variable "mcp_tools" {
  description = "MCP tool allow list"
  type        = list(string)
  default     = []
}
