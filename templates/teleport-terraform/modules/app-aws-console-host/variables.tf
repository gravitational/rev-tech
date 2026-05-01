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
  description = "EC2 instance type for the shared app host"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "host_env" {
  description = "Host node env label for SSH/node access"
  type        = string
  default     = "prod"
}

variable "host_team" {
  description = "Host node team label for SSH/node access"
  type        = string
  default     = "platform"
}

variable "app_env" {
  description = "App label env for static AWS console apps"
  type        = string
  default     = "dev"
}

variable "app_a_name" {
  description = "Name of AWS console app A"
  type        = string
  default     = "awsconsole-a"
}

variable "app_a_public_addr" {
  description = "Public address for AWS console app A"
  type        = string
}

variable "app_a_uri" {
  description = "URI for AWS console app A"
  type        = string
  default     = "https://console.aws.amazon.com/ec2/v2/home"
}

variable "app_a_aws_account_id" {
  description = "AWS account ID label for app A"
  type        = string
}

variable "app_a_team" {
  description = "Team label for app A"
  type        = string
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
  description = "Public address for AWS console app B"
  type        = string
  default     = ""
}

variable "app_b_uri" {
  description = "URI for AWS console app B"
  type        = string
  default     = "https://console.aws.amazon.com/ec2/v2/home"
}

variable "app_b_aws_account_id" {
  description = "AWS account ID label for app B"
  type        = string
  default     = ""
}

variable "app_b_team" {
  description = "Team label for app B"
  type        = string
  default     = "platform"
}

variable "app_b_external_id" {
  description = "Optional external ID for app B"
  type        = string
  default     = null
}

variable "assume_role_arns" {
  description = "AWS role ARNs the host instance profile can assume for AWS Console access"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Additional tags to attach to the instance"
  type        = map(string)
  default     = {}
}
