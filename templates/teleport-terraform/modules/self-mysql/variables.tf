variable "env" {
  description = "Environment name (e.g., dev, prod)"
}

variable "user" {
  description = "Tag value for resource creator"
}

variable "proxy_address" {
  description = "Teleport Proxy host (e.g., proxy.example.com)"
}

variable "teleport_version" {
  description = "Teleport version to install (e.g., 16.0.0)"
}

variable "teleport_db_ca" {
  description = "Teleport DB CA cert from /webapi/auth/export"
}

variable "mysql_hostname" {
  description = "Hostname for MySQL server (used in TLS cert)"
  default     = "mysql.example.internal"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
}

variable "instance_type" {
  description = "EC2 instance type (e.g., t3.small)"
}

variable "subnet_id" {
  description = "Optional: existing subnet ID to use"
  type        = string
}

variable "security_group_ids" {
  description = "Optional: existing security group IDs"
  type        = list(string)
}

variable "team" {
  description = "Team label for the MySQL database"
  type        = string
  default     = "engineering"
}