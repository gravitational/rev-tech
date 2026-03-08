variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "okta_metadata_url" {
  description = "Okta SAML metadata URL"
  type        = string
}
