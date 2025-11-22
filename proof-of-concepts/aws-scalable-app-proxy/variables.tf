variable "name" {
  description = "Name to use for provisioned resources"
}

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
  description = "ASG scaling configuration"
  type = object({
    max_size : number
    min_size : number
    desired : number
  })
}

variable "ami" {
  description = "AMI lookup instructions"
  type = object({
    discovery_node : object({
      ami : string
      owner : string
    })
  })
}

variable "proxy" {
  description = "Teleport proxy address"
}

variable "tags" {
  description = "Set of tags to apply resources"
  type = map(string)
}