variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "env" {
  description = "Environment label"
  type        = string
  default     = "prod"
}

variable "team" {
  description = "Team label"
  type        = string
  default     = "platform"
}

variable "teleport_namespace" {
  description = "Kubernetes namespace where Teleport is installed"
  type        = string
  default     = "teleport-cluster"
}

variable "db_password" {
  description = "Master password for the Access Graph PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "teleport_host_ca" {
  description = "PEM-encoded Teleport host CA certificate. Retrieve with: curl 'https://<proxy>/webapi/auth/export?type=tls-host'"
  type        = string
}

variable "access_graph_chart_version" {
  description = "Helm chart version for teleport-access-graph (empty = latest)"
  type        = string
  default     = ""
}
