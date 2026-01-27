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
  bot_name = "ansible"
  user     = lower(split("@", var.user)[0])
}

data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_string" "bot_token" {
  length           = 32
  special          = true
  override_special = "-.+"
}

resource "teleport_provision_token" "bot" {
  version = "v2"
  metadata = {
    expires     = timeadd(timestamp(), "1h")
    name        = random_string.bot_token.result
    description = "Provision token for Machine ID bot ${local.bot_name}"
  }
  spec = {
    roles       = ["Bot"]
    bot_name    = local.bot_name
    join_method = "token"
  }
}

resource "teleport_role" "machine" {
  version = "v7"
  metadata = {
    name        = "ansible-machine-role"
    description = "Role for Machine ID host access"
  }
  spec = {
    allow = {
      logins      = ["ec2-user", local.user]
      node_labels = { "tier" = [var.env], "team" = [var.team] }
    }
  }
}

resource "teleport_bot" "host" {
  metadata = {
    name = local.bot_name
  }

  spec = {
    roles = [teleport_role.machine.id]
  }
}

resource "random_string" "token" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "main" {
  version = "v2"
  spec = {
    roles = ["Node"]
    name  = random_string.token.result
  }
  metadata = {
    expires = timeadd(timestamp(), "1h")
  }
}

resource "aws_instance" "ansible_host" {
  ami                    = data.aws_ami.linux.id
  instance_type          = "t3.small"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids

  user_data = templatefile("${path.module}/userdata.tpl", {
    env              = var.env
    team             = var.team
    proxy_address    = var.proxy_address
    teleport_version = var.teleport_version
    bot_token        = teleport_provision_token.bot.metadata.name
    node_token       = teleport_provision_token.main.metadata.name
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

  tags = {
    Name = "${local.user}-${var.env}-${local.bot_name}"
  }
}
