##################################################################################
# modules/teleport-rbac/main.tf
#
# Canonical Teleport RBAC role set for demo environments.
# Used by control-plane/cloud and control-plane/standalone.
# (The eks control plane — now in github.com/tenaciousdlg/teleport-terraform —
# manages the same roles via TeleportRoleV7 CRDs.)
#
# No variables — all role definitions are static. Label values are the
# canonical demo defaults: dev/dev and prod/platform.
# Provider must be configured by the calling root module.
#
# Numeric enums used below (Terraform provider uses proto enum ints).
#
# THE PREVIOUS VERSION OF THIS COMMENT WAS WRONG. It claimed "1 = keep", so
# every role here set create_host_user_mode = 1, which is OFF. Host user
# creation was silently disabled in every deployment built from this module.
# Values verified against the provider schema; read the schema, not a comment:
#
#   terraform providers schema -json | jq '...options.create_host_user_mode'
#
#   create_host_user_mode: 0 = unspecified, 1 = off, 2 = drop (gone in v15+),
#                          3 = KEEP, 4 = insecure-drop
#   create_db_user_mode:   0 = unspecified, 1 = off, 2 = KEEP,
#                          3 = best_effort_drop      <-- DIFFERENT numbering!
#   require_session_mfa:   0 = off, 1 = session, 2 = session_and_hardware_key,
#                          3 = hardware_key_touch, 4 = hardware_key_pin,
#                          5 = hardware_key_touch_and_pin
#
# ONE BAD ROLE POISONS A HOST. Teleport disables host user creation for a node
# if ANY role matching that node leaves the mode off or UNSET, so a read-only
# role cancels a privileged role's keep. That is why prod-readonly-access below
# sets 3 rather than 0 -- it matches prod nodes, and leaving it unspecified
# disabled creation for every other role on those hosts. The roles reference
# documents how explicit values combine but is silent on unset; this was
# confirmed empirically on a live cluster 2026-09-21.
#
# THE NODE ALSO NEEDS `visudo`. Teleport's host user management hard-requires
# it, and without the sudo package the agent reports this at DEBUG severity
# ONLY:
#     Skipping host user management ... missing required binaries: visudo
#     Not creating host user: node has disabled host user creation
# while every session fails with "Failed to launch: user: unknown user X".
# At INFO level that is indistinguishable from an RBAC fault. If "unknown
# user" survives correct roles, raise the agent to DEBUG before touching RBAC.
##################################################################################

terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 18.0"
    }
  }
}

##################################################################################
# BASE ROLE
##################################################################################

resource "teleport_role" "base_user" {
  version = "v7"

  metadata = {
    name        = "base-user"
    description = "Base authenticated user with minimal permissions"
  }

  spec = {
    options = {
      max_session_ttl    = "8h0m0s"
      enhanced_recording = ["command", "network"]
    }

    allow = {
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
    }
  }
}

##################################################################################
# DEV ACCESS
##################################################################################

resource "teleport_role" "dev_access" {
  version = "v7"

  metadata = {
    name        = "dev-access"
    description = "Standing access to dev resources for the dev team"
  }

  spec = {
    options = {
      max_session_ttl                = "8h0m0s"
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 3 # keep
      create_host_user_default_shell = "/bin/bash"
      create_db_user                 = true
      create_desktop_user            = true
      desktop_clipboard              = true
      desktop_directory_sharing      = true
      pin_source_ip                  = false
    }

    allow = {
      app_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      aws_role_arns = ["{{external.aws_role_arns}}"]
      db_labels = {
        env                      = ["dev"]
        team                     = ["dev"]
        "teleport.dev/db-access" = ["mapped"]
      }
      db_names       = ["{{external.db_names}}", "*"]
      db_users       = ["{{external.db_users}}", "reader", "writer"]
      desktop_groups = ["Administrators"]
      host_groups    = ["wheel"]
      logins = [
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
      join_sessions = [
        {
          name  = "Join dev sessions"
          roles = ["dev-access", "platform-dev-access"]
          kinds = ["k8s", "ssh"]
          modes = ["moderator", "observer"]
        }
      ]
      mcp = {
        tools = ["*"]
      }
      node_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
      windows_desktop_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      windows_desktop_logins = ["{{email.local(external.username)}}"]
    }
  }
}

##################################################################################
# DEV AUTO ACCESS (RDS — auto user provisioning)
##################################################################################

resource "teleport_role" "dev_auto_access" {
  version = "v7"

  metadata = {
    name        = "dev-auto-access"
    description = "Dev access with auto user provisioning for RDS databases"
  }

  spec = {
    options = {
      max_session_ttl                = "8h0m0s"
      enhanced_recording             = ["command", "network"]
      create_db_user                 = true
      create_db_user_mode            = 2 # keep (db users: 2, NOT 3)
      create_host_user_mode          = 3 # keep
      create_host_user_default_shell = "/bin/bash"
    }

    allow = {
      db_labels = {
        env                      = ["dev"]
        team                     = ["dev"]
        "teleport.dev/db-access" = ["auto"]
      }
      db_names    = ["{{external.db_names}}", "*"]
      db_roles    = ["{{external.db_roles}}", "reader", "writer", "dbadmin"]
      db_users    = ["{{email.local(external.username)}}", "{{email.local(external.email)}}"]
      host_groups = ["wheel"]
      logins = [
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}"
      ]
      node_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
    }
  }
}

##################################################################################
# PLATFORM DEV ACCESS (cross-team dev access for platform/engineering)
##################################################################################

resource "teleport_role" "platform_dev_access" {
  version = "v7"

  metadata = {
    name        = "platform-dev-access"
    description = "Standing access to all dev resources for the platform team"
  }

  spec = {
    options = {
      max_session_ttl                = "8h0m0s"
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 3 # keep
      create_host_user_default_shell = "/bin/bash"
      create_db_user                 = true
      create_db_user_mode            = 2 # keep (db users: 2, NOT 3)
      create_desktop_user            = false
      desktop_clipboard              = true
      desktop_directory_sharing      = true
      pin_source_ip                  = false
    }

    allow = {
      app_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      aws_role_arns = ["{{external.aws_role_arns}}"]
      db_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      db_names = ["{{external.db_names}}", "*"]
      db_users = [
        "{{external.db_users}}",
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "reader", "writer"
      ]
      desktop_groups = ["Administrators"]
      host_groups    = ["wheel"]
      join_sessions = [
        {
          name  = "Join dev sessions"
          roles = ["dev-access", "platform-dev-access"]
          kinds = ["k8s", "ssh"]
          modes = ["moderator", "observer"]
        }
      ]
      logins = [
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
      mcp = {
        tools = ["*"]
      }
      node_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] },
        { resources = ["access_graph"], verbs = ["list", "read"] }
      ]
      windows_desktop_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      windows_desktop_logins = ["{{email.local(external.username)}}"]
    }
  }
}

##################################################################################
# PROD READONLY ACCESS (requires approval)
##################################################################################

resource "teleport_role" "prod_readonly_access" {
  version = "v7"

  metadata = {
    name        = "prod-readonly-access"
    description = "Read-only access to prod resources (requires approval)"
  }

  spec = {
    options = {
      max_session_ttl       = "4h0m0s"
      enhanced_recording    = ["command", "network"]
      create_host_user_mode = 3 # keep -- NOT 0: unset here poisoned every prod node
      create_db_user        = false
      create_db_user_mode   = 0
    }

    allow = {
      app_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      db_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      db_names = ["*"]
      db_users = ["reader", "reporting", "{{external.readonly_db_user}}"]
      logins   = ["readonly", "{{external.readonly_login}}"]
      mcp = {
        tools = ["*"]
      }
      node_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
      windows_desktop_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
    }
  }
}

##################################################################################
# PROD ACCESS (full prod, requires approval, per-session MFA)
##################################################################################

resource "teleport_role" "prod_access" {
  version = "v7"

  metadata = {
    name        = "prod-access"
    description = "Full access to prod resources (requires approval)"
  }

  spec = {
    options = {
      max_session_ttl                = "2h0m0s"
      require_session_mfa            = 1
      enhanced_recording             = ["command", "network"]
      create_host_user_mode          = 3 # keep
      create_host_user_default_shell = "/bin/bash"
      create_db_user                 = true
      create_db_user_mode            = 2 # keep (db users: 2, NOT 3)
      create_desktop_user            = false
      desktop_clipboard              = true
      desktop_directory_sharing      = true
      pin_source_ip                  = false
    }

    allow = {
      app_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      aws_role_arns = ["{{external.aws_role_arns}}"]
      db_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      db_names = ["{{external.db_names}}", "*"]
      db_users = [
        "{{external.db_users}}",
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "reader", "writer"
      ]
      desktop_groups = ["Administrators"]
      host_groups    = ["wheel"]
      join_sessions = [
        {
          name  = "Join prod sessions"
          roles = ["*"]
          kinds = ["k8s", "ssh"]
          modes = ["moderator", "observer"]
        }
      ]
      logins = [
        "{{external.logins}}",
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
      mcp = {
        tools = ["*"]
      }
      node_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
      windows_desktop_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      windows_desktop_logins = ["{{email.local(external.username)}}", "Administrator"]
    }
  }
}

##################################################################################
# PROD AUTO ACCESS (RDS auto user provisioning, requires approval)
##################################################################################

resource "teleport_role" "prod_auto_access" {
  version = "v7"

  metadata = {
    name        = "prod-auto-access"
    description = "Prod access with auto user provisioning for RDS databases (requires approval)"
  }

  spec = {
    options = {
      max_session_ttl                = "2h0m0s"
      enhanced_recording             = ["command", "network"]
      create_db_user                 = true
      create_db_user_mode            = 2 # keep (db users: 2, NOT 3)
      create_host_user_mode          = 3 # keep
      create_host_user_default_shell = "/bin/bash"
    }

    allow = {
      db_labels = {
        env                      = ["prod"]
        team                     = ["platform"]
        "teleport.dev/db-access" = ["auto"]
      }
      db_names    = ["{{external.db_names}}", "*"]
      db_roles    = ["{{external.db_roles}}", "reader", "writer", "dbadmin"]
      db_users    = ["{{email.local(external.username)}}", "{{email.local(external.email)}}"]
      host_groups = ["wheel"]
      logins = [
        "{{external.logins}}",
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
      node_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
    }
  }
}

##################################################################################
# REQUEST ROLES
##################################################################################

resource "teleport_role" "dev_requester" {
  version = "v7"

  metadata = {
    name        = "dev-requester"
    description = "Devs can request prod-readonly-access"
  }

  spec = {
    allow = {
      request = {
        roles           = [teleport_role.prod_readonly_access.metadata.name]
        search_as_roles = [teleport_role.prod_readonly_access.metadata.name]
        max_duration    = "8h"
      }
    }
  }
}

resource "teleport_role" "senior_dev_requester" {
  version = "v7"

  metadata = {
    name        = "senior-dev-requester"
    description = "Senior devs can request prod-readonly, prod-access, and prod-auto-access"
  }

  spec = {
    allow = {
      request = {
        roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
        search_as_roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
        max_duration = "8h"
      }
    }
  }
}

resource "teleport_role" "prod_requester" {
  version = "v7"

  metadata = {
    name        = "prod-requester"
    description = "Platform engineers can request prod-readonly, prod-access, and prod-auto-access"
  }

  spec = {
    allow = {
      request = {
        roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
        search_as_roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
        max_duration = "8h"
      }
    }
  }
}

##################################################################################
# REVIEW ROLES
##################################################################################

resource "teleport_role" "dev_reviewer" {
  version = "v7"

  metadata = {
    name        = "dev-reviewer"
    description = "Can approve dev access requests"
  }

  spec = {
    allow = {
      review_requests = {
        roles = [
          teleport_role.dev_access.metadata.name,
          teleport_role.platform_dev_access.metadata.name
        ]
        preview_as_roles = [
          teleport_role.dev_access.metadata.name,
          teleport_role.platform_dev_access.metadata.name
        ]
      }
    }
  }
}

resource "teleport_role" "prod_reviewer" {
  version = "v7"

  metadata = {
    name        = "prod-reviewer"
    description = "Can approve prod access requests"
  }

  spec = {
    allow = {
      review_requests = {
        roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
        preview_as_roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name,
          teleport_role.prod_auto_access.metadata.name
        ]
      }
    }
  }
}
