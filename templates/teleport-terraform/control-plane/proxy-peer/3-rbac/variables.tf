variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "okta_metadata_url" {
  description = "Okta SAML metadata URL"
  type        = string
}

variable "dev_env" {
  description = "Environment label for dev"
  type        = string
  default     = "dev"
}

variable "prod_env" {
  description = "Environment label for prod"
  type        = string
  default     = "prod"
}

variable "dev_team" {
  description = "Team label for dev"
  type        = string
  default     = "dev"
}

variable "prod_team" {
  description = "Team label for prod"
  type        = string
  default     = "platform"
}
