name = "teleport-demo-aws-proxy"

cidr = "10.112.0.0/16"

instance_type = "t3a.micro"

capacity = {
  max_size = 6
  min_size = 1
  desired  = 3
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
]

ami = {
  discovery_node = {
    ami   = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    owner = "099720109477"
  }
}

proxy = null
tags  = null