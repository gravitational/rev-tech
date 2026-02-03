##################################################################################
# CONFIGURATION - Terraform
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
# PROVIDERS
##################################################################################
provider "teleport" {
  addr = "${var.proxy_address}:443"
}

##################################################################################
# SAML CONNECTOR + AUTH PREFERENCE
##################################################################################

resource "teleport_saml_connector" "okta" {
  version = "v2"

  metadata = {
    name = "okta"
  }

  spec = {
    attributes_to_roles = [
      {
        name  = "groups"
        value = "Everyone"
        roles = ["base-user"]
      }
    ]

    acs                     = "https://${var.proxy_address}/v1/webapi/saml/acs/okta"
    entity_descriptor_url   = var.okta_metadata_url
    service_provider_issuer = "https://${var.proxy_address}/v1/webapi/saml/acs/okta"
  }
}

resource "teleport_auth_preference" "main" {
  depends_on = [teleport_saml_connector.okta]

  version = "v2"

  metadata = {
    description = "auth preference"
    labels = {
      name                  = "cluster-auth-preference"
      "teleport.dev/origin" = "dynamic"
    }
  }

  spec = {
    type          = "saml"
    second_factor = "on"

    webauthn = {
      rp_id = var.proxy_address
    }

    connector_name     = teleport_saml_connector.okta.metadata.name
    allow_local_auth   = true
    allow_passwordless = true
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
        {
          resources = ["event"]
          verbs     = ["list", "read"]
        },
        {
          resources = ["session"]
          verbs     = ["read", "list"]
        }
      ]
    }
  }
}

##################################################################################
# ENV ACCESS ROLES
##################################################################################
resource "teleport_role" "dev_access" {
  version = "v7"
  metadata = {
    name        = "dev-access"
    description = "Standing access to dev resources for the dev team"
  }

  spec = {
    allow = {
      app_labels = {
        env  = [var.dev_env]
        team = [var.dev_team]
      }
      db_labels = {
        env  = [var.dev_env]
        team = [var.dev_team]
      }
      node_labels = {
        env  = [var.dev_env]
        team = [var.dev_team]
      }
      windows_desktop_labels = {
        env  = [var.dev_env]
        team = [var.dev_team]
      }
      logins = ["{{email.local(external.username)}}", "ubuntu", "ec2-user"]
    }
  }
}

resource "teleport_role" "platform_dev_access" {
  version = "v7"
  metadata = {
    name        = "platform-dev-access"
    description = "Standing access to all dev resources for platform"
  }

  spec = {
    allow = {
      app_labels = {
        env  = [var.dev_env]
        team = ["*"]
      }
      db_labels = {
        env  = [var.dev_env]
        team = ["*"]
      }
      node_labels = {
        env  = [var.dev_env]
        team = ["*"]
      }
      windows_desktop_labels = {
        env  = [var.dev_env]
        team = ["*"]
      }
      logins = ["{{email.local(external.username)}}", "ubuntu", "ec2-user"]
    }
  }
}

resource "teleport_role" "prod_readonly_access" {
  version = "v7"
  metadata = {
    name        = "prod-readonly-access"
    description = "Read-only access to prod resources"
  }

  spec = {
    allow = {
      app_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      db_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      node_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      windows_desktop_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      logins = ["readonly", "{{external.readonly_login}}"]
    }
  }
}

resource "teleport_role" "prod_access" {
  version = "v7"
  metadata = {
    name        = "prod-access"
    description = "Full access to prod resources"
  }

  spec = {
    allow = {
      app_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      db_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      node_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      windows_desktop_labels = {
        env  = [var.prod_env]
        team = [var.prod_team]
      }
      logins = ["{{external.logins}}", "root", "admin", "ec2-user", "ubuntu"]
    }

    options = {
      require_session_mfa = 1
    }
  }
}

##################################################################################
# REQUEST / REVIEW ROLES
##################################################################################
resource "teleport_role" "dev_requester" {
  version = "v7"
  metadata = {
    name        = "dev-requester"
    description = "Dev users can request higher access"
  }

  spec = {
    allow = {
      request = {
        roles = [
          teleport_role.platform_dev_access.metadata.name,
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name
        ]
        search_as_roles = [
          teleport_role.platform_dev_access.metadata.name,
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name
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
    description = "Platform users can request prod access"
  }

  spec = {
    allow = {
      request = {
        roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name
        ]
        search_as_roles = [
          teleport_role.prod_readonly_access.metadata.name,
          teleport_role.prod_access.metadata.name
        ]
        max_duration = "8h"
      }
    }
  }
}

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

##################################################################################
# ACCESS LISTS (SCIM-managed)
##################################################################################
resource "teleport_access_list" "everyone" {
  header = {
    version = "v1"
    metadata = {
      name = "everyone"
    }
  }

  spec = {
    title       = "Everyone"
    description = "All users in the organization"
    type        = "scim"

    owners = [
      {
        name        = "admin"
        description = "Platform team admin"
      }
    ]

    grants = {
      roles = [
        teleport_role.base_user.metadata.name
      ]
    }
  }
}

resource "teleport_access_list" "devs" {
  header = {
    version = "v1"
    metadata = {
      name = "devs"
    }
  }

  spec = {
    title       = "devs"
    description = "Standing dev access for the dev team"
    type        = "scim"

    owners = [
      {
        name        = "admin"
        description = "Platform team admin"
      }
    ]

    grants = {
      roles = [
        teleport_role.dev_access.metadata.name,
        teleport_role.dev_requester.metadata.name
      ]
    }
  }
}

resource "teleport_access_list" "engineers" {
  header = {
    version = "v1"
    metadata = {
      name = "engineers"
    }
  }

  spec = {
    title       = "engineers"
    description = "Platform team: standing dev access, dev approvals, prod requests"
    type        = "scim"

    owners = [
      {
        name        = "admin"
        description = "Platform team admin"
      }
    ]

    grants = {
      roles = [
        teleport_role.platform_dev_access.metadata.name,
        teleport_role.dev_reviewer.metadata.name,
        teleport_role.prod_requester.metadata.name
      ]
    }
  }
}

output "rbac_summary" {
  value = {
    roles = [
      teleport_role.base_user.id,
      teleport_role.dev_access.id,
      teleport_role.platform_dev_access.id,
      teleport_role.prod_readonly_access.id,
      teleport_role.prod_access.id,
      teleport_role.dev_requester.id,
      teleport_role.prod_requester.id,
      teleport_role.dev_reviewer.id
    ]

    access_lists = [
      teleport_access_list.everyone.id,
      teleport_access_list.devs.id,
      teleport_access_list.engineers.id
    ]
  }
}
