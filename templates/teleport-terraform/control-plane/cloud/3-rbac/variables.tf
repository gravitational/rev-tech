variable "proxy_address" {
  description = "Teleport proxy hostname (no scheme, no port)"
  type        = string
}

variable "devs" {
  description = "Usernames (emails) to add to the devs access list"
  type        = list(string)
  default     = []
}

variable "senior_devs" {
  description = "Usernames (emails) to add to the senior-devs access list"
  type        = list(string)
  default     = []
}

variable "engineers" {
  description = "Usernames (emails) to add to the engineers access list"
  type        = list(string)
  default     = []
}

variable "autoupdate_mode" {
  description = "Agent auto-update mode: 'enabled' for automatic rolling updates, 'disabled' to manage manually"
  type        = string
  default     = "enabled"
}
