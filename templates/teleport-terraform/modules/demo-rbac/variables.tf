variable "name_prefix" {
  description = "Prefix for all Teleport role names (e.g. the SE's username) so concurrent deployments on a shared cluster don't collide"
  type        = string
}

variable "env" {
  description = "Environment label the dev role matches — must equal the env label on the deployed resources"
  type        = string
}

variable "prod_env" {
  description = "Environment label of the prod resources behind the access-request flow. Set to null to skip the prod/requester/reviewer roles."
  type        = string
  default     = null
}

variable "team" {
  description = "Team label the roles match — must equal the team label on the deployed resources"
  type        = string
}

variable "create_demo_user" {
  description = "Create a local demo user with the dev + requester roles. Activate it after apply with: tctl users reset <demo_user_name>"
  type        = bool
  default     = true
}

variable "demo_user_name" {
  description = "Name of the local demo user (the developer persona). Note: usernames are cluster-global — override on shared clusters."
  type        = string
  default     = "bob"
}

variable "logins" {
  description = "OS logins the roles allow"
  type        = list(string)
  default     = ["ec2-user", "ubuntu"]
}

variable "db_users" {
  description = "Database users the dev role allows (must exist on the demo databases)"
  type        = list(string)
  default     = ["reader", "writer"]
}

variable "request_max_duration" {
  description = "Maximum duration of an approved access request (JIT window)"
  type        = string
  default     = "1h"
}
