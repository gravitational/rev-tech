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

variable "onboarding_initial_public_key" {
  description = "Optional SSH public key for preregistered bound keypair onboarding"
  type        = string
  default     = ""
}

variable "bound_keypair_recovery_limit" {
  description = "Maximum number of bound keypair recovery rejoins allowed"
  type        = number
  default     = 10
}

variable "bound_keypair_recovery_mode" {
  description = "Bound keypair recovery mode: standard, relaxed, or insecure"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "relaxed", "insecure"], var.bound_keypair_recovery_mode)
    error_message = "bound_keypair_recovery_mode must be one of: standard, relaxed, insecure."
  }
}
