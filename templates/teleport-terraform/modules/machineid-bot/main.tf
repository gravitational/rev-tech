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
  length  = 32
  special = false
}

# The bound_keypair registration secret is SET in the token spec
# (spec.bound_keypair.onboarding.registration_secret) and handed to tbot, not
# read back from status: the 18.x provider's status is optional, not computed,
# so a server-generated secret never reaches state. Skipped when a public key
# is preregistered instead.
resource "random_password" "registration_secret" {
  count   = var.join_method == "bound_keypair" && var.onboarding_initial_public_key == "" ? 1 : 0
  length  = 32
  special = false
}

# Two token resources because the two join methods have different spec shapes,
# which a conditional expression cannot unify. Exactly one exists.
resource "teleport_provision_token" "bot" {
  count      = var.join_method == "bound_keypair" ? 1 : 0
  depends_on = [teleport_bot.this]

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
      onboarding = local.onboarding
      recovery = {
        mode  = var.bound_keypair_recovery_mode
        limit = var.bound_keypair_recovery_limit
      }
    }
  }
}

# iam join: the host signs sts:GetCallerIdentity with its instance-profile role
# and Teleport matches the assumed-role ARN against allow. No secret exists.
resource "teleport_provision_token" "bot_iam" {
  count      = var.join_method == "iam" ? 1 : 0
  depends_on = [teleport_bot.this]

  version = "v2"
  metadata = {
    name        = random_string.bot_token.result
    description = "IAC: iam join for Machine ID bot ${var.bot_name}"
  }
  spec = {
    roles       = ["Bot"]
    bot_name    = var.bot_name
    join_method = "iam"
    allow       = var.iam_allow
  }
}

moved {
  from = teleport_provision_token.bot
  to   = teleport_provision_token.bot[0]
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
  onboarding = var.onboarding_initial_public_key != "" ? {
    initial_public_key  = var.onboarding_initial_public_key
    registration_secret = null
    } : {
    initial_public_key  = null
    registration_secret = one(random_password.registration_secret[*].result)
  }
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
