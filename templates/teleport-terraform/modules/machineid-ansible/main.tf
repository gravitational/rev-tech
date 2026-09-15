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
  bot_name = "${var.bot_name_prefix}-${random_string.bot_suffix.result}"
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

resource "random_string" "bot_suffix" {
  length  = 4
  upper   = false
  special = false
}

module "machineid_bot" {
  source = "../machineid-bot"

  bot_name       = local.bot_name
  role_name      = "ansible-machine-role"
  allowed_logins = ["ec2-user", local.user]
  node_labels    = { "env" = [var.env], "team" = [var.team] }
  # No onboarding key: Teleport generates a one-time registration secret for
  # the token, tbot redeems it on first start, and the keypair is born on the
  # host — Terraform never sees or stores private key material. Recovery uses
  # the module defaults (mode "standard", limit 10) instead of "insecure".
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
  # Ensure bot role/user resources exist in Teleport before tbot starts on boot.
  depends_on = [module.machineid_bot]

  ami                    = data.aws_ami.linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids

  user_data = templatefile("${path.module}/userdata.tpl", {
    env                 = var.env
    team                = var.team
    proxy_address       = var.proxy_address
    bot_token           = module.machineid_bot.bot_token
    registration_secret = module.machineid_bot.bot_registration_secret
    node_token          = teleport_provision_token.main.metadata.name
  })

  lifecycle {
    precondition {
      condition     = module.machineid_bot.bot_registration_secret != null
      error_message = "The bot token exposed no registration secret (provider too old, or an onboarding key was preregistered) — tbot would have nothing to join with."
    }
  }

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
