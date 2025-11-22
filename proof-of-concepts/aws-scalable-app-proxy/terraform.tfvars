name = "teleport-demo-awscli-proxy"

cidr = "10.112.0.0/16"

instance_type = "t3a.micro"

capacity = {
  max_size = 3
  min_size = 1
  desired  = 2
}

firewall_rules = [
  # ====== Egress =========
  {
    ingress   = false
    proto     = "-1"
    action    = "allow"
    cidr      = "0.0.0.0/0"
    from_port = 0
    to_port   = 0
  },

  # ====== Ingress =========
  {
    ingress   = true
    proto     = "tcp"
    action    = "allow"
    cidr      = "0.0.0.0/0"
    from_port = 22
    to_port   = 22
  },
]

ami = {
  discovery_node = {
    ami   = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
    owner = "099720109477"
  }
}

proxy = null
tags  = null