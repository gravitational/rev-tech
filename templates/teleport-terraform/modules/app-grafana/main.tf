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

resource "teleport_provision_token" "grafana" {
  version = "v2"
  metadata = {
    expires = timeadd(timestamp(), "8h")
  }
  spec = {
    roles = ["App", "Node"]
    name  = random_string.token.result
  }
  # timestamp() changes on every plan, causing perpetual drift noise.
  # The token only needs to live long enough for the instance to boot and register.
  lifecycle {
    ignore_changes = [metadata]
  }
}

resource "aws_instance" "grafana" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  # Teleport nodes register via outbound reverse tunnel — no public IP needed.
  associate_public_ip_address = false
  vpc_security_group_ids      = var.security_group_ids

  user_data = templatefile("${path.module}/userdata.tpl", {
    name             = "${var.env}-grafana"
    token            = teleport_provision_token.grafana.metadata.name
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    env              = var.env
    user             = local.user
    team             = var.team
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = "${local.user}-${var.env}-grafana"
  })
}
