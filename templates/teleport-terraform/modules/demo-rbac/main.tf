##################################################################################
# modules/demo-rbac/main.tf
#
# Per-profile demo RBAC: the roles and local user a profile's demo narrative
# needs, generated from the profile's own env/team variables so the labels
# always match the deployed resources.
#
# Role names are prefixed with var.name_prefix so two SEs can deploy the same
# profile on one cluster without colliding. On a dedicated cluster (event or
# canonical deployment) set name_prefix = "" to get the unprefixed names the
# published demo docs use: dev-access, staging-access, prod-access,
# prod-access-mfa. The requester/reviewer pair keeps a "demo-" prefix when
# unprefixed because the `requester` and `reviewer` preset roles already
# exist on every cluster.
#
# The JIT trio (created with the prod flow):
#   staging-access   requestable, auto-approved by policy when
#                    auto_approve_reason is set (access_monitoring_rule)
#   prod-access      requestable, human approval required
#   prod-access-mfa  requestable, human approval + per-session MFA
#
# Unlike modules/teleport-rbac (the deploy-once, cluster-canonical role set
# managed from control-plane), this module is instantiated per profile and
# torn down with it.
#
# Numeric enums (Terraform provider uses proto enum ints — verify against the
# provider schema, the values are NOT sequential/obvious):
#   create_host_user_mode:  0 = unspecified  1 = OFF  3 = keep  4 = insecure-drop
#                           (2 = drop, removed in v15+)
#   require_session_mfa:    0 = off  1 = per-session webauthn
#                           2..5 = hardware-key variants (require YubiKeys)
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

  # "" -> unprefixed canonical names; anything else -> "<prefix>-"
  p = var.name_prefix == "" ? "" : "${var.name_prefix}-"

  # requester/reviewer collide with cluster preset roles when unprefixed
  dp = var.name_prefix == "" ? "demo-" : "${var.name_prefix}-"

  creator = var.name_prefix == "" ? "demo-rbac" : var.name_prefix
}

##################################################################################
# DEV ACCESS — standing access to the profile's dev-labeled resources
##################################################################################

resource "teleport_role" "dev_access" {
  version = "v7"

  metadata = {
    name        = "${local.p}dev-access"
    description = "Demo: standing access to ${var.env}-labeled resources"
  }

  spec = {
    options = {
      max_session_ttl                = "8h0m0s"
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 3
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
        tools = var.mcp_tools
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
      # Persona-named Windows login first ({{internal.windows_logins}} resolves to
      # the user's own trait, e.g. "bob"), generic logins as fallback. With
      # create_desktop_user, first RDP login creates the local Windows account
      # under the persona's name: the identity story on the Windows side.
      windows_desktop_logins = concat(["{{internal.windows_logins}}"], var.logins)
    }
  }
}

##################################################################################
# MCP READ-WRITE — full MCP toolset on one app, for the identity-contrast beat.
# Teleport filters denied tools out of the MCP tools/list response, so a client
# holding only the dev role's read-only allowlist is never even offered
# write_file. Grant this role to one identity (e.g. the SEs via connector
# mapping) and List Tools side by side with the persona: same server, same
# request, different toolset per identity.
##################################################################################

resource "teleport_role" "mcp_rw" {
  count   = var.mcp_rw_app == null ? 0 : 1
  version = "v7"

  metadata = {
    name        = "${local.p}${var.mcp_rw_app}-rw"
    description = "Demo: all MCP tools on the ${var.mcp_rw_app} app (contrast with ${local.p}dev-access's read-only allowlist)"
  }

  spec = {
    allow = {
      app_labels = {
        "teleport.dev/app" = [var.mcp_rw_app]
      }
      mcp = {
        tools = ["*"]
      }
    }
  }
}

##################################################################################
# STAGING ACCESS — requestable elevation over the dev-labeled resources.
# The auto-approve access_monitoring_rule below targets this role only, so
# the booth flow is: staging approves by policy, prod needs a human.
##################################################################################

resource "teleport_role" "staging_access" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.p}staging-access"
    description = "Demo: requestable elevated access to ${var.env}-labeled resources (auto-approved by policy when the reason matches)"
  }

  spec = {
    options = {
      max_session_ttl                = "4h0m0s"
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 3
      create_host_user_default_shell = "/bin/bash"
      create_db_user                 = false
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
      db_names    = ["*"]
      db_users    = var.db_users
      host_groups = ["wheel"]
      logins      = var.logins
      node_labels = {
        env  = [var.env]
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
# PROD ACCESS — only reachable through an approved access request
##################################################################################

resource "teleport_role" "prod_access" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.p}prod-access"
    description = "Demo: access to ${var.prod_env}-labeled resources, granted only via an approved access request"
  }

  spec = {
    options = {
      max_session_ttl       = "4h0m0s"
      enhanced_recording    = ["command", "network"]
      create_host_user_mode = 1
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

resource "teleport_role" "prod_access_mfa" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.p}prod-access-mfa"
    description = "Demo: ${var.prod_env} access via access request, with per-session MFA re-verification"
  }

  spec = {
    options = {
      max_session_ttl       = "1h0m0s"
      enhanced_recording    = ["command", "network"]
      create_host_user_mode = 1
      create_db_user        = false
      require_session_mfa   = 1
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

resource "teleport_role" "requester" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.dp}requester"
    description = "Demo: can request ${local.p}staging-access, ${local.p}prod-access, ${local.p}prod-access-mfa"
  }

  spec = {
    allow = {
      request = {
        roles = [
          teleport_role.staging_access[0].metadata.name,
          teleport_role.prod_access[0].metadata.name,
          teleport_role.prod_access_mfa[0].metadata.name,
        ]
        search_as_roles = [
          teleport_role.staging_access[0].metadata.name,
          teleport_role.prod_access[0].metadata.name,
          teleport_role.prod_access_mfa[0].metadata.name,
        ]
        max_duration = var.request_max_duration
      }
    }
  }
}

resource "teleport_role" "reviewer" {
  count   = local.create_prod ? 1 : 0
  version = "v7"

  metadata = {
    name        = "${local.dp}reviewer"
    description = "Demo: can approve requests for the ${local.p}staging/prod access roles"
  }

  spec = {
    allow = {
      review_requests = {
        roles = [
          teleport_role.staging_access[0].metadata.name,
          teleport_role.prod_access[0].metadata.name,
          teleport_role.prod_access_mfa[0].metadata.name,
        ]
        preview_as_roles = [
          teleport_role.staging_access[0].metadata.name,
          teleport_role.prod_access[0].metadata.name,
          teleport_role.prod_access_mfa[0].metadata.name,
        ]
      }
      # Live-join the demo personas' SSH sessions (observer or moderator) —
      # the "watch, then lock" beat. Matches sessions hosted by holders of
      # the demo access roles.
      join_sessions = [{
        name = "join-demo-sessions"
        roles = [
          teleport_role.dev_access.metadata.name,
          teleport_role.staging_access[0].metadata.name,
          teleport_role.prod_access[0].metadata.name,
          teleport_role.prod_access_mfa[0].metadata.name,
        ]
        kinds = ["ssh"]
        modes = ["observer", "moderator"]
      }]
    }
  }
}

##################################################################################
# AUTO-APPROVE — policy-driven review: staging-access requests whose reason
# contains var.auto_approve_reason are approved by the builtin integration.
# Prod roles always require a human review.
##################################################################################

resource "teleport_access_monitoring_rule" "auto_approve_staging" {
  count   = local.create_prod && var.auto_approve_reason != null ? 1 : 0
  version = "v1"

  metadata = {
    name        = "${local.dp}auto-approve-staging"
    description = "Demo: auto-approve ${local.p}staging-access requests when the reason contains \"${var.auto_approve_reason}\""
  }

  spec = {
    subjects = ["access_request"]
    # Exact-match on the reason: request_reason is a string, and the predicate
    # language's contains()/regexp.match() only operate on sets (set()-wrapping
    # passes validation but silently never matches at evaluation — verified on
    # v18.10). The request reason must therefore EQUAL auto_approve_reason.
    condition     = "access_request.spec.roles.contains(\"${teleport_role.staging_access[0].metadata.name}\") && access_request.spec.request_reason == \"${var.auto_approve_reason}\""
    desired_state = "reviewed"
    automatic_review = {
      integration = "builtin"
      decision    = "APPROVED"
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
    description = "Demo developer persona (local user)"
    labels = {
      "teleport.dev/creator" = local.creator
    }
  }

  spec = {
    roles = concat(
      [teleport_role.dev_access.metadata.name],
      local.create_prod ? [teleport_role.requester[0].metadata.name] : [],
      var.extra_role_names
    )
    # Windows RDP login named after the persona (consumed by the dev role's
    # {{internal.windows_logins}} template).
    traits = {
      windows_logins = [var.demo_user_name]
    }
  }
}

# One persona per demo workstation: same roles as the primary demo user, so
# concurrent demos don't share sessions, requests, or the lock blast radius.
resource "teleport_user" "extra_demo_users" {
  for_each = var.create_demo_user ? toset(var.extra_demo_user_names) : toset([])
  version  = "v2"

  metadata = {
    name        = each.value
    description = "Demo developer persona (local user)"
    labels = {
      "teleport.dev/creator" = local.creator
    }
  }

  spec = {
    roles = concat(
      [teleport_role.dev_access.metadata.name],
      local.create_prod ? [teleport_role.requester[0].metadata.name] : [],
      var.extra_role_names
    )
    traits = {
      windows_logins = [each.value]
    }
  }
}
