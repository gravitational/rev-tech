# 3-rbac/variables.tf

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "proxy_address" {
  description = "Name of your Teleport cluster (e.g. teleport.example.com)"
  type        = string
}

variable "okta_metadata_url" {
  description = "Okta SAML metadata URL"
  type        = string
}

variable "okta_preview_metadata_url" {
  description = "Okta preview SAML metadata URL (optional)"
  type        = string
  default     = ""
}

variable "enable_okta_preview" {
  description = "Whether to enable the Okta preview SAML connector"
  type        = bool
  default     = false
}

variable "teleport_namespace" {
  description = "Namespace where Teleport is installed"
  type        = string
  default     = "teleport-cluster"
}

variable "dev_team" {
  description = "Team label for dev environment resources"
  type        = string
  default     = "dev"
}

variable "prod_team" {
  description = "Team label for prod environment resources"
  type        = string
  default     = "platform"
}

variable "autoupdate_mode" {
  description = "Agent auto-update mode: 'enabled' for automatic rolling updates, 'disabled' to manage manually"
  type        = string
  default     = "enabled"
}
