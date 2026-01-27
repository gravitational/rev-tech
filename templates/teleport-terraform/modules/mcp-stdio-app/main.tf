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
  user          = lower(split("@", var.user)[0])
  mcp_args_json = jsonencode(var.mcp_args)
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "app" {
  version = "v2"
  metadata = {
    expires = timeadd(timestamp(), "1h")
    name    = random_string.token.result
  }
  spec = {
    roles = ["App"]
  }
}

resource "aws_instance" "mcp_app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = var.security_group_ids

  user_data = templatefile("${path.module}/userdata.tpl", {
    name             = "${var.env}-${var.app_name}"
    token            = teleport_provision_token.app.metadata.name
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    env              = var.env
    team             = var.team
    app_name         = var.app_name
    app_description  = var.app_description
    mcp_command      = var.mcp_command
    mcp_args_json    = local.mcp_args_json
    run_as_host_user = var.run_as_host_user
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
    Name = "${local.user}-${var.env}-${var.app_name}"
  })
}
