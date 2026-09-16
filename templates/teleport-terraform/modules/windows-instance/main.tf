terraform {
  required_providers {
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

resource "random_string" "windows" {
  length  = 40
  special = false
}

resource "aws_instance" "windows" {
  # Demo hosts keep the AMI they were created with — data.aws_ami uses
  # most_recent, and a new upstream image must not replace healthy
  # instances on the next apply (e.g. mid-event).
  lifecycle {
    ignore_changes = [ami]
  }

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  user_data = templatefile("${path.module}/windows.tpl", {
    User            = local.user
    Password        = random_string.windows.result
    Domain          = var.proxy_address
    Env             = var.env
    TeleportVersion = var.teleport_version
  })
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    encrypted             = true
    delete_on_termination = true
  }
  tags = {
    Name = "${local.user}-${var.env}-windows"
  }
}
