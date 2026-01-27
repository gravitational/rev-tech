# machineid-host
terraform {
  required_providers {
    teleport = {
      source = "terraform.releases.teleport.dev/gravitational/teleport"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  bot_name = var.bot_name
  user     = lower(split("@", var.user)[0])
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

resource "teleport_bot" "host" {
  name     = local.bot_name
  token_id = teleport_provision_token.bot.metadata.name
  roles    = [teleport_role.machine.id]
}

resource "teleport_role" "machine" {
  version = "v7"
  metadata = {
    name        = var.role_name
    description = "Role for Machine ID host access"
  }
  spec = {
    allow = {
      logins      = var.allowed_logins
      node_labels = var.node_labels
    }
  }
}
