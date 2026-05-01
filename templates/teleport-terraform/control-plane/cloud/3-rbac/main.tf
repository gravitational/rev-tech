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
# RBAC — shared role module
# Manages all 12 demo roles. State migration: if you have existing role resources
# in state, run terraform state mv before applying:
#   terraform state mv teleport_role.base_user module.rbac.teleport_role.base_user
#   (repeat for each role that was previously managed here)
##################################################################################
module "rbac" {
  source = "../../../modules/teleport-rbac"
}

##################################################################################
# ACCESS LISTS — static (Terraform-managed membership)
#
# These mirror the SCIM-driven access lists in the EKS control plane.
# Populate var.devs / var.senior_devs / var.engineers in terraform.tfvars.
#
# The SAML connector's attributes_to_roles handles base-user assignment
# automatically for all authenticated users, so no "everyone" list is needed.
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
