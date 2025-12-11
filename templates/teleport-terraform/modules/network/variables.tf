variable "cidr_public_subnet" {
  type        = string
  description = "CIDR block for the public subnet"
}

variable "cidr_secondary_subnet" {
  type        = string
  description = "CIDR block for the secondary private subnet"
  default     = ""
}

variable "cidr_subnet" {
  type        = string
  description = "CIDR block for the private subnet"
}

variable "cidr_vpc" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "create_db_subnet_group" {
  type        = bool
  description = "Create a DB subnet group for RDS"
  default     = false
}

variable "create_secondary_subnet" {
  type        = bool
  description = "Create a secondary private subnet (required for RDS)"
  default     = false
}

variable "env" {
  type        = string
  description = "Environment label for tagging"
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for resource names/Name tags; defaults to env if empty."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources in this module."
  default     = {}
}
