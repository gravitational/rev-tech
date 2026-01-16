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

module "host_identity" {
  source = "../machineid_host"

  bot_name         = local.bot_name
  user             = var.user
  env              = var.env
  proxy_address    = var.proxy_address
  teleport_version = var.teleport_version
  role_name        = "ansible-machine-role"
  allowed_logins   = ["ec2-user", local.user]
  node_labels = {
    "tier" = [var.env],
    "team" = [var.team]
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
    bot_token        = module.host_identity.bot_token
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