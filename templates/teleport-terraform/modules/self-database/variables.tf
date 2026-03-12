variable "db_type" {
  description = "Database engine: postgres, mysql, mongodb, or cassandra"
  type        = string
  validation {
    condition     = contains(["postgres", "mysql", "mongodb", "cassandra"], var.db_type)
    error_message = "db_type must be one of: postgres, mysql, mongodb, cassandra"
  }
}

variable "db_hostname" {
  description = "Hostname for the database server (used in TLS cert SAN)"
  type        = string
  default     = "db.example.internal"
}

variable "env" {
  description = "Environment label (e.g., dev, prod)"
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

variable "teleport_db_ca" {
  description = "Teleport DB CA cert from /webapi/auth/export"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (e.g., t3.small)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs for the instance"
  type        = list(string)
}

variable "team" {
  description = "Team label for the database"
  type        = string
  default     = "platform"
}
