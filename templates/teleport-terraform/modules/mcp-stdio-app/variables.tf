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

variable "app_name" {
  description = "MCP app name"
  type        = string
}

variable "app_description" {
  description = "MCP app description"
  type        = string
  default     = "MCP stdio server"
}

variable "mcp_command" {
  description = "Command to launch the stdio MCP server"
  type        = string
  default     = "docker"
}

variable "mcp_args" {
  description = "Arguments to launch the stdio MCP server"
  type        = list(string)
  default     = ["run", "-i", "--rm", "mcp/everything"]
}

variable "run_as_host_user" {
  description = "Host user to run the MCP server as"
  type        = string
  default     = "docker"
}

variable "team" {
  description = "Team label for MCP server"
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Additional tags to attach to each instance"
  type        = map(string)
  default     = {}
}
