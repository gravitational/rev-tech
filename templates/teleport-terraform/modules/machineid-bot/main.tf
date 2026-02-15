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

resource "random_string" "bot_token" {
  length           = 32
  special          = true
  override_special = "-.+"
}

resource "random_string" "registration_secret" {
  length  = 32
  special = false
}

resource "teleport_provision_token" "bot" {
  version = "v2"
  metadata = {
    name        = random_string.bot_token.result
    description = "Provision token for Machine ID bot ${var.bot_name}"
  }
  spec = {
    roles       = ["Bot"]
    bot_name    = var.bot_name
    join_method = "bound_keypair"
    bound_keypair = {
      onboarding = {
        registration_secret = random_string.registration_secret.result
      }
      recovery = {
        mode  = "standard"
        limit = 1
      }
    }
  }
}

resource "teleport_role" "machine" {
  version = "v7"
  metadata = {
    name        = var.role_name
    description = "Role for Machine ID bot access"
  }
  spec = {
    allow = local.allow
  }
}

locals {
  allow = merge(
    length(var.allowed_logins) > 0 ? { logins = var.allowed_logins } : {},
    length(var.node_labels) > 0 ? { node_labels = var.node_labels } : {},
    length(var.app_labels) > 0 ? { app_labels = var.app_labels } : {},
    length(var.mcp_tools) > 0 ? { mcp = { tools = var.mcp_tools } } : {}
  )
}

resource "teleport_bot" "this" {
  metadata = {
    name = var.bot_name
  }

  spec = {
    roles = [teleport_role.machine.id]
  }
}
