variable "name" {}

variable "cidr" {
  description = "CIDR range to provision the VPC with"
}

variable "instance_type" {
  default = "t3a.small"
}

variable "firewall_rules" {
  description = "Security Group rules to enforce"
  type = list(object({
    ingress   = bool
    proto     = string
    action    = string
    cidr      = string
    from_port = number
    to_port   = number
  }))
}

variable "capacity" {
  type = object({
    max_size : number
    min_size : number
    desired : number
  })
}

variable "ami" {
  type = object({
    discovery_node : object({
      ami : string
      owner : string
    })
  })
}

variable "proxy" {}

variable "tags" {
  type = map(string)
}