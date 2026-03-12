variable "proxy_address" {
  description = "Name of your Teleport cluster (e.g. teleport.example.com)"
  type        = string
}

variable "okta_metadata_url" {
  description = "Okta SAML metadata URL"
  type        = string
}
