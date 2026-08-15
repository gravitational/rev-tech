variable "name_prefix" {
  description = "Prefix for all Teleport role names (e.g. the SE's username) so concurrent deployments on a shared cluster don't collide. Set to \"\" on a dedicated cluster for the canonical unprefixed names (dev-access, staging-access, prod-access, prod-access-mfa; requester/reviewer become demo-requester/demo-reviewer to avoid the cluster presets)."
  type        = string
}

variable "auto_approve_reason" {
  description = "When set, creates an access_monitoring_rule that auto-approves staging-access requests whose reason exactly equals this phrase (builtin integration; the predicate language has no substring match for strings). null disables auto-approval. Only applies when prod_env is set."
  type        = string
  default     = null
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

variable "extra_demo_user_names" {
  description = "Additional local demo users with the same roles as the primary one — one persona per demo workstation so concurrent demos (and the lock beat) don't collide. Each needs its own one-time activation."
  type        = list(string)
  default     = []
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

variable "mcp_tools" {
  description = "MCP tool allowlist for the dev role (glob patterns). Default allows all; set read-only patterns (e.g. [\"read_*\", \"list_*\"]) to demo AI tool-call denial + audit."
  type        = list(string)
  default     = ["*"]
}

variable "mcp_rw_app" {
  description = "When set (e.g. \"mcp-filesystem\"), also create <prefix><value>-rw granting all MCP tools on apps labeled teleport.dev/app=<value>. Grant it to one identity and not another for the MCP Inspector list-tools contrast: same server, different toolset per identity."
  type        = string
  default     = null
}

variable "extra_role_names" {
  description = "Names of roles created outside this module to also attach to the demo users — e.g. linux-desktop-access, which lives in modules/linux-desktop because its role fields need the v19 provider."
  type        = list(string)
  default     = []
}

variable "request_max_duration" {
  description = "Maximum duration of an approved access request (JIT window)"
  type        = string
  default     = "1h"
}
