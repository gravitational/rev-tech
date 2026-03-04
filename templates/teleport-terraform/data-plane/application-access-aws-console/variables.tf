variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "user" {
  description = "Tag value for resource creator"
  type        = string
}

variable "proxy_address" {
  description = "Teleport Proxy address (without https)"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to install on the app host"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for shared app service host"
  type        = string
  default     = "t3.micro"
}

variable "host_env" {
  description = "Node label env for the shared app host"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Node label team for the shared app host"
  type        = string
  default     = "platform"
}

variable "env" {
  description = "App label env for AWS console applications"
  type        = string
  default     = "dev"
}

variable "app_a_name" {
  description = "Name of AWS console app A"
  type        = string
  default     = "awsconsole-a"
}

variable "app_a_public_addr" {
  description = "Public address for AWS console app A (optional; defaults to awsa.<proxy_address>)"
  type        = string
  default     = ""
}

variable "app_a_uri" {
  description = "URI for AWS console app A"
  type        = string
  default     = "https://console.aws.amazon.com/ec2/v2/home"
}

variable "app_a_aws_account_id" {
  description = "AWS account ID label for awsconsole-a"
  type        = string
  validation {
    condition     = can(regex("^\\d{12}$", var.app_a_aws_account_id))
    error_message = "app_a_aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "app_a_team" {
  description = "Team label for awsconsole-a"
  type        = string
  default     = "dev"
}

variable "app_b_aws_account_id" {
  description = "AWS account ID label for awsconsole-b"
  type        = string
  default     = ""
  validation {
    condition = (
      !var.enable_app_b ||
      can(regex("^\\d{12}$", var.app_b_aws_account_id))
    )
    error_message = "When enable_app_b is true, app_b_aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "app_b_name" {
  description = "Name of AWS console app B"
  type        = string
  default     = "awsconsole-b"
}

variable "enable_app_b" {
  description = "Whether to configure a second AWS console app (app B)"
  type        = bool
  default     = false
}

variable "app_b_public_addr" {
  description = "Public address for AWS console app B (optional; defaults to awsconsole-b.<proxy_address>)"
  type        = string
  default     = ""
}

variable "app_b_uri" {
  description = "URI for AWS console app B"
  type        = string
  default     = "https://console.aws.amazon.com/ec2/v2/home"
}

variable "app_b_team" {
  description = "Team label for awsconsole-b"
  type        = string
  default     = "platform"
}

variable "app_b_external_id" {
  description = "Optional external ID for awsconsole-b"
  type        = string
  default     = null
  validation {
    condition     = var.app_b_external_id == null || trimspace(var.app_b_external_id) != ""
    error_message = "If set, app_b_external_id cannot be an empty string."
  }
}

variable "assume_role_arns" {
  description = "Additional AWS role ARNs this app host can assume via instance metadata credentials"
  type        = list(string)
  default     = []
}

variable "manage_account_a_roles" {
  description = "Whether to create and manage account A IAM roles in this Terraform stack"
  type        = bool
  default     = false
}

variable "account_a_roles" {
  description = "IAM roles to create/manage in account A and expose through Teleport AWS Console access"
  type = map(object({
    policy_arns                 = list(string)
    additional_trust_principals = list(string)
    allow_account_root          = bool
  }))
  default = {
    TeleportReadOnlyAccess = {
      policy_arns                 = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      additional_trust_principals = []
      allow_account_root          = false
    }
    TeleportEC2Access = {
      policy_arns                 = ["arn:aws:iam::aws:policy/AmazonEC2FullAccess"]
      additional_trust_principals = []
      allow_account_root          = false
    }
    TeleportAdminAccess = {
      policy_arns                 = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      additional_trust_principals = []
      allow_account_root          = true
    }
  }
  validation {
    condition = (
      !var.manage_account_a_roles ||
      length(var.account_a_roles) > 0 ||
      length(var.assume_role_arns) > 0
    )
    error_message = "When manage_account_a_roles is true, define account_a_roles or provide assume_role_arns."
  }
  validation {
    condition = (
      var.manage_account_a_roles ||
      length(var.assume_role_arns) > 0 ||
      length(var.account_a_roles) > 0
    )
    error_message = "When manage_account_a_roles is false, provide assume_role_arns or account_a_roles role names for existing roles."
  }
}

variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "cidr_public_subnet" {
  description = "CIDR block for the public subnet (NAT gateway)"
  type        = string
  default     = "10.0.0.0/24"
}
