# 2-teleport/variables.tf

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "env" {
  description = "Environment label for shared infrastructure (e.g., dev, prod)"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Team label for shared infrastructure (e.g., platform)"
  type        = string
  default     = "platform"
}

variable "proxy_address" {
  description = "Name of your Teleport cluster (e.g. teleport.example.com)"
  type        = string
}

variable "domain_name" {
  description = "Route53 hosted zone name for DNS records and cert-manager ACME DNS-01 validation (e.g. teleportdemo.com). Required — this layer creates DNS records and TLS certificates that depend on it."
  type        = string
  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must be set to your Route53 hosted zone name (e.g. export TF_VAR_domain_name=teleportdemo.com). Omitting it silently skips DNS record creation and breaks TLS certificate issuance."
  }
}

variable "user" {
  description = "Email for Teleport admin and ACME certificate"
  type        = string
}

variable "teleport_version" {
  description = "Teleport version to deploy (e.g. 18.0.0)"
  type        = string
}

variable "use_dns_validation" {
  description = "Use DNS-01 validation instead of HTTP-01"
  type        = bool
  default     = true # Recommended for wildcard certificates
}

variable "certificate_duration" {
  description = "Certificate validity duration"
  type        = string
  default     = "2160h" # 90 days
}

variable "access_graph_enabled" {
  description = "Enable Access Graph integration. Deploy 5-access-graph first, then re-apply this layer with this set to true."
  type        = bool
  default     = false
}
