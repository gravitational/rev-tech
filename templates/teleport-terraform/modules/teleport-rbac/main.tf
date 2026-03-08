##################################################################################
# modules/teleport-rbac/main.tf
#
# Canonical Teleport RBAC role set for demo environments.
# Used by control-plane/cloud and control-plane/proxy-peer.
# (control-plane/eks manages the same roles via TeleportRoleV7 CRDs.)
#
# No variables — all role definitions are static. Label values are the
# canonical demo defaults: dev/dev and prod/platform.
# Provider must be configured by the calling root module.
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
      max_session_ttl    = "8h0m0s"
      enhanced_recording = ["command", "network"]
    }

    allow = {
      app_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      db_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
      logins = [
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
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
      max_session_ttl    = "8h0m0s"
      enhanced_recording = ["command", "network"]
    }

    allow = {
      db_labels = {
        env  = ["dev"]
        team = ["dev"]
      }
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
      max_session_ttl    = "8h0m0s"
      enhanced_recording = ["command", "network"]
    }

    allow = {
      app_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      db_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      logins = [
        "{{email.local(external.username)}}",
        "{{email.local(external.email)}}",
        "ubuntu", "ec2-user"
      ]
      node_labels = {
        env  = ["dev"]
        team = ["*"]
      }
      rules = [
        { resources = ["event"], verbs = ["list", "read"] },
        { resources = ["session"], verbs = ["read", "list"] }
      ]
      windows_desktop_labels = {
        env  = ["dev"]
        team = ["*"]
      }
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
      max_session_ttl    = "4h0m0s"
      enhanced_recording = ["command", "network"]
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
      logins = ["readonly", "{{external.readonly_login}}"]
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
      max_session_ttl     = "2h0m0s"
      require_session_mfa = 1
      enhanced_recording  = ["command", "network"]
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
      windows_desktop_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
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
      max_session_ttl    = "2h0m0s"
      enhanced_recording = ["command", "network"]
    }

    allow = {
      db_labels = {
        env  = ["prod"]
        team = ["platform"]
      }
      logins = [
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
