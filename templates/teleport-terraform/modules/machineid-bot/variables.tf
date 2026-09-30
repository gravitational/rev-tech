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

variable "join_method" {
  description = "Bot join method: bound_keypair, or iam for a bot running on EC2 (strongest attestation, no secret)"
  type        = string
  default     = "bound_keypair"
  validation {
    condition     = contains(["bound_keypair", "iam"], var.join_method)
    error_message = "join_method must be bound_keypair or iam."
  }
}

variable "iam_allow" {
  description = "iam join allow rules (aws_account + assumed-role aws_arn). Required when join_method = iam."
  type = list(object({
    aws_account = string
    aws_arn     = string
  }))
  default = []
}
