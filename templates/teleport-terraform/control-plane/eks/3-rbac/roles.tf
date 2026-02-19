##################################################################################
# TELEPORT CLUSTER RESOURCES (CRDs)
##################################################################################

# SAML Connectors
resource "kubectl_manifest" "saml_connector_okta" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportSAMLConnector"
    metadata = {
      name      = "okta-integrator"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      acs = "https://${var.proxy_address}:443/v1/webapi/saml/acs/okta"
      attributes_to_roles = [
        { name = "groups", value = "Everyone", roles = ["base-user"] }
      ]
      display                 = "okta dlg"
      entity_descriptor_url   = var.okta_metadata_url
      service_provider_issuer = "https://${var.proxy_address}/sso/saml/metadata"
    }
  })
}

resource "kubectl_manifest" "saml_connector_okta_preview" {
  count = var.enable_okta_preview ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v2"
    kind       = "TeleportSAMLConnector"
    metadata = {
      name      = "okta-preview"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      acs = "https://${var.proxy_address}/v1/webapi/saml/acs/okta-preview"
      attributes_to_roles = [
        { name = "groups", value = "Solutions-Engineering", roles = ["auditor", "access", "editor"] }
      ]
      display                 = "okta preview"
      entity_descriptor_url   = var.okta_preview_metadata_url
      service_provider_issuer = "https://${var.proxy_address}/sso/saml/metadata"
    }
  })
}

# Login Rules
resource "kubectl_manifest" "login_rule_okta" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportLoginRule"
    metadata = {
      name      = "okta-preferred-login-rule"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      priority = 0
      traits_map = {
        logins = ["external.logins", "strings.lower(external.username)"]
        groups = ["external.groups"]
      }
      traits_expression = <<-EOT
        external.put("logins",
          choose(
            option(external.groups.contains("okta"), "okta"),
            option(true, "local")
          )
        )
      EOT
    }
  })
}

# Base user role
resource "kubectl_manifest" "role_base_user" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "base-user"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      allow = {
        rules = [
          { resources = ["event"], verbs = ["list", "read"] },
          { resources = ["session"], verbs = ["read", "list"] }
        ]
      }
      options = {
        max_session_ttl    = "8h0m0s"
        enhanced_recording = ["command", "network"]
      }
    }
  })
}

# Dev/Prod Access Roles, Reviewers, Requesters, Access Lists

##################################################################################
# DEV/PROD ACCESS ROLES (TeleportRoleV7)
##################################################################################

resource "kubectl_manifest" "role_dev_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name        = "dev-access"
      namespace   = data.kubernetes_namespace.teleport_cluster.metadata[0].name
      description = "Development access for mapped user databases and infrastructure"
    }
    spec = {
      allow = {
        app_labels = {
          env  = ["dev"]
          team = [var.dev_team]
        }
        aws_role_arns = ["{{external.aws_role_arns}}"]
        db_labels = {
          env                      = ["dev"]
          team                     = [var.dev_team]
          "teleport.dev/db-access" = ["mapped"]
        }
        db_names       = ["{{external.db_names}}", "*"]
        db_users       = ["{{external.db_users}}", "reader", "writer"]
        desktop_groups = ["Administrators"]
        impersonate = {
          roles = ["Db"]
          users = ["Db"]
        }
        join_sessions = [
          {
            kinds = ["k8s", "ssh"]
            modes = ["moderator", "observer"]
            name  = "Join dev sessions"
            roles = ["dev-access", "platform-dev-access"]
          }
        ]
        kubernetes_groups = ["{{external.kubernetes_groups}}", "system:masters"]
        kubernetes_labels = {
          env  = "dev"
          team = var.dev_team
        }
        kubernetes_resources = [
          { kind = "*", name = "*", namespace = "dev", verbs = ["*"] }
        ]
        logins = ["{{external.logins}}", "{{email.local(external.username)}}", "{{email.local(external.email)}}"]
        mcp = {
          tools = ["*"]
        }
        node_labels = {
          env  = ["dev"]
          team = [var.dev_team]
        }
        rules = [
          { resources = ["event"], verbs = ["list", "read"] },
          { resources = ["session"], verbs = ["read", "list"] }
        ]
        windows_desktop_labels = {
          env  = ["dev"]
          team = [var.dev_team]
        }
        windows_desktop_logins = ["{{external.windows_logins}}", "{{email.local(external.username)}}"]
      }
      options = {
        create_db_user                 = false
        create_desktop_user            = false
        create_host_user_mode          = "keep"
        create_host_user_default_shell = "/bin/bash"
        desktop_clipboard              = true
        desktop_directory_sharing      = true
        max_session_ttl                = "8h0m0s"
        pin_source_ip                  = false
        enhanced_recording             = ["command", "network"]
      }
    }
  })
}

resource "kubectl_manifest" "role_platform_dev_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name        = "platform-dev-access"
      namespace   = data.kubernetes_namespace.teleport_cluster.metadata[0].name
      description = "Standing access to all dev resources for platform"
    }
    spec = {
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
        db_names       = ["{{external.db_names}}", "*"]
        db_users       = ["{{external.db_users}}", "reader", "writer"]
        desktop_groups = ["Administrators"]
        join_sessions = [
          {
            kinds = ["k8s", "ssh"]
            modes = ["moderator", "observer"]
            name  = "Join dev sessions"
            roles = ["dev-access", "platform-dev-access"]
          }
        ]
        kubernetes_groups = ["{{external.kubernetes_groups}}", "system:masters"]
        kubernetes_labels = {
          env  = "dev"
          team = "*"
        }
        kubernetes_resources = [
          { kind = "*", name = "*", namespace = "dev", verbs = ["*"] }
        ]
        logins = ["{{external.logins}}", "{{email.local(external.username)}}", "{{email.local(external.email)}}"]
        mcp = {
          tools = ["*"]
        }
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
        windows_desktop_logins = ["{{external.windows_logins}}", "{{email.local(external.username)}}"]
      }
      options = {
        create_db_user                 = false
        create_desktop_user            = false
        create_host_user_mode          = "keep"
        create_host_user_default_shell = "/bin/bash"
        desktop_clipboard              = true
        desktop_directory_sharing      = true
        max_session_ttl                = "8h0m0s"
        pin_source_ip                  = false
        enhanced_recording             = ["command", "network"]
      }
    }
  })
}


resource "kubectl_manifest" "role_prod_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name        = "prod-access"
      namespace   = data.kubernetes_namespace.teleport_cluster.metadata[0].name
      description = "Full access to production resources"
    }
    spec = {
      allow = {
        app_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        aws_role_arns = ["{{external.aws_role_arns}}"]
        db_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        db_names       = ["{{external.db_names}}", "*"]
        db_users       = ["{{external.db_users}}", "reader", "writer"]
        desktop_groups = ["Administrators"]
        impersonate = {
          roles = ["Db"]
          users = ["Db"]
        }
        join_sessions = [
          {
            kinds = ["k8s", "ssh"]
            modes = ["moderator", "observer"]
            name  = "Join prod sessions"
            roles = ["*"]
          }
        ]
        kubernetes_groups = ["{{external.kubernetes_groups}}", "system:masters"]
        kubernetes_labels = {
          env  = "prod"
          team = var.prod_team
        }
        kubernetes_resources = [
          { kind = "*", name = "*", namespace = "prod", verbs = ["*"] }
        ]
        logins = ["{{external.logins}}", "{{email.local(external.username)}}", "{{email.local(external.email)}}", "ubuntu", "ec2-user"]
        mcp = {
          tools = ["*"]
        }
        node_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        rules = [
          { resources = ["event"], verbs = ["list", "read"] },
          { resources = ["session"], verbs = ["read", "list"] }
        ]
        windows_desktop_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        windows_desktop_logins = ["{{external.windows_logins}}", "{{email.local(external.username)}}", "Administrator"]
      }
      options = {
        create_db_user                 = false
        create_desktop_user            = false
        create_host_user_mode          = "keep"
        create_host_user_default_shell = "/bin/bash"
        desktop_clipboard              = true
        desktop_directory_sharing      = true
        max_session_ttl                = "2h0m0s"
        pin_source_ip                  = false
        enhanced_recording             = ["command", "network"]
        require_session_mfa            = "session"
      }
    }
  })
}

resource "kubectl_manifest" "role_prod_readonly_access" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name        = "prod-readonly-access"
      namespace   = data.kubernetes_namespace.teleport_cluster.metadata[0].name
      description = "Read-only access to production resources"
    }
    spec = {
      allow = {
        app_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        db_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        db_names = ["*"]
        db_users = ["reader", "reporting", "{{external.readonly_db_user}}"]
        mcp = {
          tools = ["*"]
        }
        kubernetes_labels = {
          env  = "prod"
          team = var.prod_team
        }
        kubernetes_resources = [
          { kind = "*", name = "*", namespace = "prod", verbs = ["get", "list", "watch"] }
        ]
        node_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        windows_desktop_labels = {
          env  = ["prod"]
          team = [var.prod_team]
        }
        windows_desktop_logins = ["{{external.windows_logins}}", "Administrator"]
      }
      options = {
        max_session_ttl       = "4h0m0s"
        create_host_user_mode = "off"
        create_db_user        = false
        create_db_user_mode   = "off"
        enhanced_recording    = ["command", "network"]
      }
    }
  })
}


resource "kubectl_manifest" "role_prod_requester" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "prod-requester"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      allow = {
        request = {
          roles           = ["prod-readonly-access", "prod-access"]
          search_as_roles = ["prod-readonly-access", "prod-access"]
        }
      }
    }
  })
}

resource "kubectl_manifest" "role_dev_requester" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "dev-requester"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      allow = {
        request = {
          roles           = ["platform-dev-access", "prod-readonly-access", "prod-access"]
          search_as_roles = ["platform-dev-access", "prod-readonly-access", "prod-access"]
        }
      }
    }
  })
}

resource "kubectl_manifest" "role_dev_reviewer" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportRoleV7"
    metadata = {
      name      = "dev-reviewer"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      allow = {
        review_requests = {
          roles            = ["dev-access", "platform-dev-access"]
          preview_as_roles = ["dev-access", "platform-dev-access"]
        }
      }
    }
  })
}

# Access Lists
resource "kubectl_manifest" "access_list_everyone" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "everyone"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      title       = "Everyone"
      description = "All users in the organization"
      type        = "scim"
      owners = [
        { name = "admin", description = "Platform team admin" }
      ]
      grants = {
        roles = ["base-user"]
      }
    }
  })
}

resource "kubectl_manifest" "access_list_devs" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "devs"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      title       = "devs"
      description = "Standing dev access for the dev team"
      type        = "scim"
      owners = [
        { name = "admin", description = "Platform team admin" }
      ]
      grants = {
        roles = ["dev-access", "dev-requester"]
      }
    }
  })
}

resource "kubectl_manifest" "access_list_engineers" {
  yaml_body = yamlencode({
    apiVersion = "resources.teleport.dev/v1"
    kind       = "TeleportAccessList"
    metadata = {
      name      = "engineers"
      namespace = data.kubernetes_namespace.teleport_cluster.metadata[0].name
    }
    spec = {
      title       = "engineers"
      description = "Platform team: standing dev access, dev approvals, prod requests"
      type        = "scim"
      owners = [
        { name = "admin", description = "Platform team admin" }
      ]
      grants = {
        roles = ["platform-dev-access", "dev-reviewer", "prod-requester"]
      }
    }
  })
}
