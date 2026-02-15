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

variable "mongodb_hostname" {
  description = "Hostname for MongoDB server (used in TLS cert)"
  default     = "mongodb.example.internal"
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
  description = "Optional: existing subnet ID to use"
  type        = string
}

variable "security_group_ids" {
  description = "Optional: existing security group IDs"
  type        = list(string)
}

variable "team" {
  description = "Team label for the MongoDB database"
  type        = string
  default     = "platform"
}
