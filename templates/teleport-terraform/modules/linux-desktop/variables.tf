variable "env" {
  description = "Environment tag (e.g., dev, prod)"
  type        = string
}

variable "team" {
  description = "Team label for the desktop and SSH services"
  type        = string
  default     = "platform"
}

variable "user" {
  description = "Tag value for resource creator"
  type        = string
}

variable "proxy_address" {
  description = "Teleport proxy address (host only, no scheme or port)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 24.04 (AL2023 ships no desktop environment packages)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type — Xfce sessions inside Xvfb want the memory"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "Subnet ID to launch instance in"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
}

variable "tags" {
  description = "Extra AWS tags for the instance"
  type        = map(string)
  default     = {}
}

variable "desktop_logins" {
  description = "OS logins offered for desktop sessions. Userdata creates each one on the host (the service does not auto-create users), and the access role allows the same list."
  type        = list(string)
  default     = ["ubuntu"]
}

variable "create_access_role" {
  description = "Create the <prefix>linux-desktop-access role. Lives here rather than modules/demo-rbac because the linux_desktop_* role fields need the v19 provider."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Prefix for the access role name (e.g. the SE's username) so concurrent deployments on a shared cluster don't collide. Set to \"\" for the canonical unprefixed name (linux-desktop-access)."
  type        = string
  default     = ""
}

variable "xsessions_included" {
  description = "Regex of xsession names to offer (matched against the .desktop filename, e.g. \"^xfce$\"). Empty = offer everything found in /usr/share/xsessions."
  type        = string
  default     = ""
}

variable "xsessions_excluded" {
  description = "Regex of xsession names to hide (applied after included). Empty = hide nothing."
  type        = string
  default     = ""
}
