# ---------------------------------------------------------------------------
# Core inputs
# ---------------------------------------------------------------------------

variable "proxy_address" {
  description = "Teleport proxy address (host only, no https or port)"
  type        = string
}

variable "user" {
  description = "Username or email for resource tagging and naming"
  type        = string
}

variable "env" {
  description = "Environment label for dev resources (e.g., dev)"
  type        = string
  default     = "dev"
}

variable "prod_env" {
  description = "Environment label for the prod SSH node used in the access request demo"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Team label for Teleport RBAC"
  type        = string
  default     = "platform"
}

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-2"
}

variable "profile_label" {
  description = "Value of the Profile cost-attribution tag on all AWS resources; presets set this to their own name"
  type        = string
  default     = "custom"
}

# ---------------------------------------------------------------------------
# Use-case flags — presets/*.tfvars turn these on in archetype bundles;
# set them individually to compose your own demo.
# ---------------------------------------------------------------------------

variable "enable_ssh" {
  description = "Dev SSH nodes (count via ssh_dev_count)"
  type        = bool
  default     = false
}

variable "enable_ssh_prod" {
  description = "Prod SSH node behind the access-request flow (also creates the requester/reviewer demo roles)"
  type        = bool
  default     = false
}

variable "enable_postgres" {
  description = "Self-hosted PostgreSQL with TLS cert auth"
  type        = bool
  default     = false
}

variable "enable_mysql" {
  description = "Self-hosted MySQL (MariaDB) with TLS cert auth"
  type        = bool
  default     = false
}

variable "enable_mongodb" {
  description = "Self-hosted MongoDB with TLS cert auth"
  type        = bool
  default     = false
}

variable "enable_cassandra" {
  description = "Self-hosted Cassandra with TLS cert auth (t3.medium)"
  type        = bool
  default     = false
}

variable "enable_rds_mysql" {
  description = "RDS MySQL with IAM auth + auto user provisioning (adds secondary subnet + DB subnet group)"
  type        = bool
  default     = false
}

variable "enable_grafana" {
  description = "Grafana behind app access with JWT identity injection"
  type        = bool
  default     = false
}

variable "enable_httpbin" {
  description = "HTTPBin for inspecting Teleport-injected headers"
  type        = bool
  default     = false
}

variable "enable_demo_panel" {
  description = "Flask identity panel (reads the Teleport JWT assertion header)"
  type        = bool
  default     = false
}

variable "enable_aws_console" {
  description = "AWS Console app access with per-role IAM federation"
  type        = bool
  default     = false
}

variable "enable_windows" {
  description = "Windows Server + desktop service (browser-based RDP)"
  type        = bool
  default     = false
}

variable "enable_mcp" {
  description = "MCP stdio server + Machine ID bot (AI/Claude access, read-only tools)"
  type        = bool
  default     = false
}

variable "enable_ansible" {
  description = "Ansible host + Machine ID bot (certificate-based automation)"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Per-use-case knobs
# ---------------------------------------------------------------------------

variable "ssh_dev_count" {
  description = "Number of dev SSH nodes when enable_ssh is true"
  type        = number
  default     = 2
}

variable "demo_panel_app_repo" {
  description = "Git URL of the Flask demo panel app"
  type        = string
  default     = "https://github.com/tenaciousdlg/app-demo-panel"
}

variable "console_role_arns" {
  description = "IAM role ARNs the AWS Console app may assume"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Demo RBAC
# ---------------------------------------------------------------------------

variable "create_demo_rbac" {
  description = "Create the demo roles (user-prefixed) and local demo user the narrative uses. Set to false if your cluster already has the control-plane RBAC roles."
  type        = bool
  default     = true
}

variable "demo_user_name" {
  description = "Name of the local demo user (developer persona). Usernames are cluster-global — override on shared clusters."
  type        = string
  default     = "bob"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "cidr_vpc" {
  description = "CIDR block for the shared VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for the primary private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "cidr_secondary_subnet" {
  description = "CIDR block for the secondary private subnet (created only for RDS)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "create_nat_gateway" {
  description = "Private subnet + NAT gateway egress (adds ~$32/mo). Default: instances use the public subnet with public IPs; inbound stays blocked by the security group."
  type        = bool
  default     = false
}
