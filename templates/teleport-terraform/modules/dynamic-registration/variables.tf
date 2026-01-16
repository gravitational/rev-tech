variable "resource_type" {
  description = "Teleport resource type: database or app"
  type        = string
  default     = "database"
  validation {
    condition     = contains(["database", "app"], var.resource_type)
    error_message = "resource_type must be either 'database' or 'app'."
  }
}

variable "name" {
  description = "Name of the Teleport resource"
  type        = string
}

variable "description" {
  description = "Description for the resource"
  type        = string
  default     = ""
}

variable "protocol" {
  description = "Protocol (for databases only)"
  type        = string
  default     = ""
}

variable "uri" {
  description = "Connection URI (host:port or app URI)"
  type        = string
}

variable "ca_cert_chain" {
  description = "CA certificate chain (PEM)"
  type        = string
  default     = ""
}

variable "public_addr" {
  description = "Public address for apps"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to the resource"
  type        = map(string)
}

variable "rewrite_headers" {
  type    = list(string)
  default = []
}

variable "insecure_skip_verify" {
  type    = bool
  default = false
}

variable "db_access_pattern" {
  description = "Database access pattern: 'mapped' for pre-created users, 'auto' for auto user provisioning"
  type        = string
  default     = "mapped"
  validation {
    condition     = contains(["mapped", "auto"], var.db_access_pattern)
    error_message = "db_access_pattern must be either 'mapped' or 'auto'."
  }
}