terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
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

resource "teleport_provision_token" "demo_panel" {
  version = "v2"
  metadata = {
    expires = timeadd(timestamp(), "8h")
  }
  spec = {
    roles = ["App", "Node"]
    name  = random_string.token.result
  }
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "aws_instance" "demo_panel" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/userdata.tpl", {
    name             = "${var.env}-demo-panel"
    token            = teleport_provision_token.demo_panel.metadata.name
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    app_repo         = var.app_repo
    env              = var.env
    team             = var.team
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 30 # AL2023 AMI requires >= 30GB
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${local.user}-${var.env}-demo-panel"
  })
}
