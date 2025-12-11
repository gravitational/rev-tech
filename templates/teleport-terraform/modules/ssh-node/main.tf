terraform {
  required_providers {
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  user = lower(split("@", var.user)[0])
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "agent" {
  version = "v2"
  spec = {
    roles = ["Node"]
    name  = random_string.token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "1h")
  }
}

resource "aws_instance" "ssh_node" {
  count                       = var.agent_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/userdata.tpl", {
    token            = teleport_provision_token.agent.metadata.name
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    env              = var.env
    name             = "${var.env}-ssh-${count.index}"
    team             = var.team
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 30 # required for AMZN Linux 2023 AMI EBS size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.user}-${var.env}-ssh-${count.index}"
  }
}