variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "teleport_namespace" {
  description = "Namespace where Teleport is installed"
  type        = string
  default     = "teleport-cluster"
}

variable "plugin_namespace" {
  description = "Kubernetes namespace to deploy the Slack plugin into"
  type        = string
  default     = "teleport-plugins"
}

variable "slack_bot_token" {
  description = "Slack Bot User OAuth Token (starts with xoxb-)"
  type        = string
  sensitive   = true
}

variable "slack_channel_id" {
  description = "Slack channel ID for access request notifications (right-click channel → Copy Link, or channel About tab)"
  type        = string
}

variable "plugin_chart_version" {
  description = "Helm chart version for teleport-plugin-slack (empty = latest)"
  type        = string
  default     = ""
}
