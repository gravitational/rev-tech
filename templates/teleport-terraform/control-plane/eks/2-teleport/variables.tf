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
  description = "Parent domain name for DNS records (e.g. demo.com)."
  type        = string
  default     = ""
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
