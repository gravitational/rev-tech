##################################################################################
# CONFIGURATION
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
        roles = [module.rbac.role_names.base_user]
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
# RBAC — shared role module
# State migration: if roles were previously managed in this root module, run:
#   terraform state mv teleport_role.base_user module.rbac.teleport_role.base_user
#   (repeat for each role)
##################################################################################
module "rbac" {
  source = "../../../modules/teleport-rbac"
}

##################################################################################
# ACCESS LISTS — static (Terraform-managed membership)
#
# Mirrors the SCIM-driven access lists in the EKS control plane.
# Populate var.devs / var.senior_devs / var.engineers in terraform.tfvars.
#
# base-user is assigned to all authenticated users via the SAML connector's
# attributes_to_roles (Everyone → base-user), so no "everyone" list is needed.
##################################################################################

resource "teleport_access_list" "devs" {
  header = {
    version = "v1"
    metadata = {
      name        = "devs"
      description = "Standing dev access for the dev team"
    }
  }

  spec = {
    title       = "devs"
    description = "Standing dev access for the dev team"
    type        = "static"
    owners      = [{ name = "admin" }]
    grants = {
      roles = [
        module.rbac.role_names.dev_access,
        module.rbac.role_names.dev_auto_access,
        module.rbac.role_names.dev_requester,
      ]
    }
  }
}

resource "teleport_access_list_member" "devs" {
  for_each = toset(var.devs)

  header = {
    version  = "v1"
    metadata = { name = each.value }
  }

  spec = {
    access_list     = teleport_access_list.devs.header.metadata.name
    membership_kind = 1
    name            = each.value
  }
}

resource "teleport_access_list" "senior_devs" {
  header = {
    version = "v1"
    metadata = {
      name        = "senior-devs"
      description = "Senior devs: cross-team dev access + prod request capability"
    }
  }

  spec = {
    title       = "senior-devs"
    description = "Senior devs: cross-team dev access + prod request capability"
    type        = "static"
    owners      = [{ name = "admin" }]
    grants = {
      roles = [
        module.rbac.role_names.platform_dev_access,
        module.rbac.role_names.dev_auto_access,
        module.rbac.role_names.senior_dev_requester,
      ]
    }
  }
}

resource "teleport_access_list_member" "senior_devs" {
  for_each = toset(var.senior_devs)

  header = {
    version  = "v1"
    metadata = { name = each.value }
  }

  spec = {
    access_list     = teleport_access_list.senior_devs.header.metadata.name
    membership_kind = 1
    name            = each.value
  }
}

resource "teleport_access_list" "engineers" {
  header = {
    version = "v1"
    metadata = {
      name        = "engineers"
      description = "Platform team: standing dev access, dev approvals, prod requests"
    }
  }

  spec = {
    title       = "engineers"
    description = "Platform team: standing dev access, dev approvals, prod requests"
    type        = "static"
    owners      = [{ name = "admin" }]
    grants = {
      roles = [
        module.rbac.role_names.platform_dev_access,
        module.rbac.role_names.dev_auto_access,
        module.rbac.role_names.prod_readonly_access,
        module.rbac.role_names.dev_reviewer,
        module.rbac.role_names.prod_requester,
        module.rbac.role_names.prod_reviewer,
        "editor",
        "auditor",
      ]
    }
  }
}

resource "teleport_access_list_member" "engineers" {
  for_each = toset(var.engineers)

  header = {
    version  = "v1"
    metadata = { name = each.value }
  }

  spec = {
    access_list     = teleport_access_list.engineers.header.metadata.name
    membership_kind = 1
    name            = each.value
  }
}

##################################################################################
# AGENT MANAGED UPDATES
#
# Enables automatic rolling updates for all Teleport agents connected to this
# cluster. Agents must be installed with the updater:
#   curl https://cdn.teleport.dev/install-v<version>.sh | bash -s -- --updater
#
# The default schedule updates agents on weekdays between 02:00-04:00 UTC.
# Adjust the schedule or set mode = "disabled" to manage updates manually.
##################################################################################
resource "teleport_autoupdate_config" "main" {
  version = "v1"

  metadata = {
    name = "autoupdate-config"
  }

  spec = {
    agents = {
      mode     = var.autoupdate_mode
      strategy = "halt-on-error"
      schedules = {
        regular = [
          {
            name       = "default"
            days       = ["Mon", "Tue", "Wed", "Thu", "Fri"]
            start_hour = 2
          }
        ]
      }
    }
  }
}
