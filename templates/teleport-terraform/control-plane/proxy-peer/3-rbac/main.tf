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
# Manages all 12 demo roles. State migration: if you have existing role resources
# in state, run terraform state mv before applying:
#   terraform state mv teleport_role.base_user module.rbac.teleport_role.base_user
#   (repeat for each role that was previously managed here)
##################################################################################
module "rbac" {
  source = "../../../modules/teleport-rbac"
}

output "rbac_summary" {
  value = module.rbac.role_names
}
