##################################################################################
# modules/demo-rbac/main.tf
#
# Per-profile demo RBAC: the roles and local user a profile's demo narrative
# needs, generated from the profile's own env/team variables so the labels
# always match the deployed resources.
#
# All role names are prefixed with var.name_prefix so two SEs can deploy the
# same profile on one cluster without colliding (the demo user name is not
# prefixed by default — override demo_user_name on shared clusters).
#
# Unlike modules/teleport-rbac (the deploy-once, cluster-canonical role set
# managed from control-plane), this module is instantiated per profile and
# torn down with it.
#
# Numeric enums (Terraform provider uses proto enum ints):
#   create_host_user_mode:  0 = off  1 = keep  2 = drop
##################################################################################

terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
  }
}

locals {
  create_prod = var.prod_env != null
}

##################################################################################
# DEV ACCESS — standing access to the profile's dev-labeled resources
##################################################################################

resource "teleport_role" "dev_access" {
  version = "v7"

  metadata = {
    name        = "${var.name_prefix}-dev-access"
    description = "Demo: standing access to ${var.env}-labeled resources (${var.name_prefix})"
  }

  spec = {
    options = {
      max_session_ttl                = "8h0m0s"
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 1
      create_host_user_default_shell = "/bin/bash"
      create_db_user                 = false
      create_desktop_user            = true
      desktop_clipboard              = true
      desktop_directory_sharing      = true
      pin_source_ip                  = false
    }

    allow = {
      app_labels = {
        env  = [var.env]
        team = [var.team]
      }
      db_labels = {
        env  = [var.env]
        team = [var.team]
      }
      db_names       = ["*"]
      db_users       = var.db_users
      desktop_groups = ["Administrators"]
      host_groups    = ["wheel"]
      logins         = var.logins
      mcp = {
        tools = ["*"]
      }
      node_labels = {
        env  = [var.env]
        team = [var.team]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
      windows_desktop_labels = {
        env  = [var.env]
        team = [var.team]
      }
      windows_desktop_logins = var.logins
    }
  }
}

##################################################################################
# PROD READONLY — only reachable through an approved access request
##################################################################################

resource "teleport_role" "prod_readonly" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${var.name_prefix}-prod-readonly"
    description = "Demo: access to ${var.prod_env}-labeled resources, granted only via access request (${var.name_prefix})"
  }

  spec = {
    options = {
      max_session_ttl       = "4h0m0s"
      enhanced_recording    = ["command", "network"]
      create_host_user_mode = 0
      create_db_user        = false
    }

    allow = {
      logins = var.logins
      node_labels = {
        env  = [var.prod_env]
        team = [var.team]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
    }
  }
}

##################################################################################
# REQUESTER / REVIEWER — the JIT access-request pair
##################################################################################

resource "teleport_role" "dev_requester" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${var.name_prefix}-dev-requester"
    description = "Demo: can request ${var.name_prefix}-prod-readonly (${var.name_prefix})"
  }

  spec = {
    allow = {
      request = {
        roles           = [teleport_role.prod_readonly[0].metadata.name]
        search_as_roles = [teleport_role.prod_readonly[0].metadata.name]
        max_duration    = var.request_max_duration
      }
    }
  }
}

resource "teleport_role" "prod_reviewer" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${var.name_prefix}-prod-reviewer"
    description = "Demo: can approve requests for ${var.name_prefix}-prod-readonly (${var.name_prefix})"
  }

  spec = {
    allow = {
      review_requests = {
        roles            = [teleport_role.prod_readonly[0].metadata.name]
        preview_as_roles = [teleport_role.prod_readonly[0].metadata.name]
      }
    }
  }
}

##################################################################################
# DEMO USER — the developer persona (local user)
#
# Terraform creates the user but cannot set credentials. Activate after apply:
#   tctl users reset <demo_user_name>
# then open the reset link to set a password + MFA device. On SSO-default
# clusters, log in with: tsh login --user=<demo_user_name> --auth=local
##################################################################################

resource "teleport_user" "demo_user" {
  count   = var.create_demo_user ? 1 : 0
  version = "v2"

  metadata = {
    name        = var.demo_user_name
    description = "Demo developer persona for ${var.name_prefix} (local user)"
    labels = {
      "teleport.dev/creator" = var.name_prefix
    }
  }

  spec = {
    roles = concat(
      [teleport_role.dev_access.metadata.name],
      local.create_prod ? [teleport_role.dev_requester[0].metadata.name] : []
    )
  }
}
